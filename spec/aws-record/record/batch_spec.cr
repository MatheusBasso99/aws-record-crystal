require "../../spec_helper"

module BatchSpec
  class Planet < Aws::Record::Base
    integer_attr :id, hash_key: true
    string_attr :name, range_key: true
  end

  class Food < Aws::Record::Base
    set_table_name "FoodTable"
    integer_attr :id, hash_key: true, database_attribute_name: "Food ID"
    string_attr :dish, range_key: true
    boolean_attr :spicy
  end

  class Breakfast < Food
    boolean_attr :gluten_free
  end

  class Drink < Aws::Record::Base
    set_table_name "DrinkTable"
    integer_attr :id, hash_key: true
    string_attr :drink
  end
end

private def planets_batch(client : Aws::DynamoDB::Client) : Aws::Record::BatchWrite
  BatchSpec::Planet.configure_client(client: client)
  client.stub_responses(
    :get_item,
    Aws::DynamoDB::Types::GetItemOutput.new(item: Aws::DynamoDB::Item{"id" => 9_i64, "name" => "pluto"})
  )
  pluto = BatchSpec::Planet.find(id: 9, name: "pluto")
  raise "expected the stubbed pluto" unless pluto

  Aws::Record::Batch.write(client: client) do |db|
    db.put(BatchSpec::Planet.new(id: 1, name: "mercury"))
    db.put(BatchSpec::Planet.new(id: 2, name: "venus"))
    db.put(BatchSpec::Planet.new(id: 3, name: "earth"))
    db.put(BatchSpec::Planet.new(id: 4, name: "mars"))
    db.put(BatchSpec::Planet.new(id: 5, name: "jupiter"))
    db.put(BatchSpec::Planet.new(id: 6, name: "saturn"))
    db.put(BatchSpec::Planet.new(id: 7, name: "uranus"))
    db.put(BatchSpec::Planet.new(id: 8, name: "neptune"))
    db.delete(pluto) # sorry :(
  end
end

describe Aws::Record::Batch do
  describe ".write" do
    describe "when all operations succeed" do
      it "writes a batch of operations" do
        client = stub_client
        client.stub_responses(:batch_write_item, Aws::DynamoDB::Types::BatchWriteItemOutput.new(
          unprocessed_items: {} of String => Array(Aws::DynamoDB::Types::WriteRequest)
        ))
        planets_batch(client).should be_a(Aws::Record::BatchWrite)
      end

      it "is complete" do
        client = stub_client
        client.stub_responses(:batch_write_item, Aws::DynamoDB::Types::BatchWriteItemOutput.new(
          unprocessed_items: {} of String => Array(Aws::DynamoDB::Types::WriteRequest)
        ))
        planets_batch(client).complete?.should be_true
      end
    end

    describe "when some operations fail" do
      it "sets the unprocessed_items attribute" do
        client = stub_client
        client.stub_responses(:batch_write_item, Aws::DynamoDB::Types::BatchWriteItemOutput.new(
          unprocessed_items: {
            "planet" => [
              Aws::DynamoDB::Types::WriteRequest.new(
                put_request: Aws::DynamoDB::Types::PutRequest.new(
                  item: Aws::DynamoDB::Item{"id" => 3_i64, "name" => "earth"}
                )
              ),
              Aws::DynamoDB::Types::WriteRequest.new(
                delete_request: Aws::DynamoDB::Types::DeleteRequest.new(
                  key: Aws::DynamoDB::Item{"id" => 9_i64, "name" => "pluto"}
                )
              ),
            ],
          }
        ))
        planets_batch(client).unprocessed_items["planet"].size.should eq(2)
      end

      it "is not complete" do
        client = stub_client
        client.stub_responses(:batch_write_item, Aws::DynamoDB::Types::BatchWriteItemOutput.new(
          unprocessed_items: {
            "planet" => [Aws::DynamoDB::Types::WriteRequest.new(
              delete_request: Aws::DynamoDB::Types::DeleteRequest.new(
                key: Aws::DynamoDB::Item{"id" => 9_i64, "name" => "pluto"}
              )
            )],
          }
        ))
        planets_batch(client).complete?.should be_false
      end
    end
  end

  describe ".read" do
    describe "when all operations succeed" do
      it "reads a batch of operations and returns modeled items" do
        client = stub_client
        client.stub_responses(:batch_get_item, Aws::DynamoDB::Types::BatchGetItemOutput.new(
          responses: {
            "FoodTable" => [
              Aws::DynamoDB::Item{"Food ID" => 1_i64, "dish" => "Pasta", "spicy" => false},
              Aws::DynamoDB::Item{"Food ID" => 2_i64, "dish" => "Waffles", "spicy" => false,
                                  "gluten_free" => true},
            ],
            "DrinkTable" => [
              Aws::DynamoDB::Item{"id" => 1_i64, "drink" => "Hot Chocolate", "gluten_free" => true},
            ],
          }
        ))
        result = Aws::Record::Batch.read(client: client) do |db|
          db.find(BatchSpec::Food, id: 1, dish: "Pasta")
          db.find(BatchSpec::Breakfast, id: 2, dish: "Waffles")
          db.find(BatchSpec::Drink, id: 1)
        end

        result.should be_a(Aws::Record::BatchRead)
        result.items.size.should eq(3)

        food = result.items[0].as(BatchSpec::Food)
        food.dirty?.should be_false
        food.spicy.should be_false

        breakfast = result.items[1].as(BatchSpec::Breakfast)
        breakfast.dirty?.should be_false
        breakfast.spicy.should be_false
        breakfast.gluten_free.should be_true

        drink = result.items[2].as(BatchSpec::Drink)
        drink.dirty?.should be_false
        drink.drink.should eq("Hot Chocolate")
        drink.responds_to?(:gluten_free).should be_false
      end

      it "is complete" do
        client = stub_client
        client.stub_responses(:batch_get_item, Aws::DynamoDB::Types::BatchGetItemOutput.new(
          responses: {"FoodTable" => [Aws::DynamoDB::Item{"Food ID" => 1_i64, "dish" => "Pasta"}]}
        ))
        result = Aws::Record::Batch.read(client: client) { |db| db.find(BatchSpec::Food, id: 1, dish: "Pasta") }
        result.complete?.should be_true
      end
    end

    describe "when there are more than 100 records" do
      it "reads batch of operations and returns most processed items" do
        client = stub_client
        stub_large_batch(client)
        large_batch(client).items.size.should eq(99)
      end

      it "is not complete" do
        client = stub_client
        stub_large_batch(client)
        large_batch(client).complete?.should be_false
      end

      it "can process the remaining records by running execute" do
        client = stub_client
        stub_large_batch(client)
        result = large_batch(client)
        result.complete?.should be_false

        client.stub_responses(:batch_get_item, Aws::DynamoDB::Types::BatchGetItemOutput.new(
          responses: {"FoodTable" => [
            Aws::DynamoDB::Item{"Food ID" => 100_i64, "dish" => "Food100", "spicy" => false},
            Aws::DynamoDB::Item{"Food ID" => 101_i64, "dish" => "Food101", "spicy" => false},
          ]}
        ))
        result.execute!
        result.complete?.should be_true
        result.should be_a(Aws::Record::BatchRead)
        result.items.size.should eq(101)
      end

      it "is a enumerable" do
        client = stub_client
        stub_large_batch(client)
        result = large_batch(client)
        result.complete?.should be_false

        client.stub_responses(:batch_get_item, Aws::DynamoDB::Types::BatchGetItemOutput.new(
          responses: {"FoodTable" => [
            Aws::DynamoDB::Item{"Food ID" => 100_i64, "dish" => "Food100", "spicy" => false},
            Aws::DynamoDB::Item{"Food ID" => 101_i64, "dish" => "Food101", "spicy" => false},
          ]}
        ))
        result.each_with_index(1) do |item, expected_id|
          item.as(BatchSpec::Food).id.should eq(expected_id)
        end
        result.to_a.size.should eq(101)
      end
    end

    it "raises when a record is missing a key" do
      client = stub_client
      expect_raises(Aws::Record::Errors::KeyMissing) do
        Aws::Record::Batch.read(client: client) { |db| db.find(BatchSpec::Food, id: 1) }
      end
    end

    it "raises when there is a duplicate item key" do
      client = stub_client
      expect_raises(ArgumentError, "Provided item keys is a duplicate request") do
        Aws::Record::Batch.read(client: client) do |db|
          db.find(BatchSpec::Food, id: 1, dish: "Pancakes")
          db.find(BatchSpec::Breakfast, id: 1, dish: "Pancakes")
        end
      end
    end

    it "raises exception when BatchGetItem raises an exception" do
      client = stub_client
      client.stub_responses(:batch_get_item, "ProvisionedThroughputExceededException")
      expect_raises(Aws::DynamoDB::Errors::ProvisionedThroughputExceededException) do
        Aws::Record::Batch.read(client: client) do |db|
          db.find(BatchSpec::Food, id: 1, dish: "Omurice")
          db.find(BatchSpec::Breakfast, id: 2, dish: "Omelette")
        end
      end
    end

    it "warns when unable to model item from response" do
      client = stub_client
      client.stub_responses(:batch_get_item, Aws::DynamoDB::Types::BatchGetItemOutput.new(
        responses: {
          "FoodTable"   => [Aws::DynamoDB::Item{"Food ID" => 1_i64, "dish" => "Pasta", "spicy" => false}],
          "DinnerTable" => [Aws::DynamoDB::Item{"id" => 1_i64, "dish" => "Spaghetti"}],
        }
      ))

      messages = capture_record_logs do
        Aws::Record::Batch.read(client: client) { |db| db.find(BatchSpec::Food, id: 1, dish: "Pasta") }
      end
      messages.any?(&.includes?("Unexpected response from service")).should be_true
    end
  end
end

private def stub_large_batch(client : Aws::DynamoDB::Client) : Nil
  items = (1..99).map do |index|
    Aws::DynamoDB::Item{"Food ID" => index.to_i64, "dish" => "Food#{index}", "spicy" => false}
  end
  client.stub_responses(:batch_get_item, Aws::DynamoDB::Types::BatchGetItemOutput.new(
    responses: {"FoodTable" => items},
    unprocessed_keys: {
      "FoodTable" => Aws::DynamoDB::Types::KeysAndAttributes.new(
        keys: [Aws::DynamoDB::Item{"Food ID" => 100_i64, "dish" => "Food100"}]
      ),
    }
  ))
end

private def large_batch(client : Aws::DynamoDB::Client) : Aws::Record::BatchRead
  Aws::Record::Batch.read(client: client) do |db|
    (1..101).each { |index| db.find(BatchSpec::Food, id: index, dish: "Food#{index}") }
  end
end

# Parity: 14/14 examples from spec/aws-record/record/batch_spec.rb (aws-record 2.15.1)
