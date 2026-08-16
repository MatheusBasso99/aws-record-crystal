require "../spec_helper"

module IntegrationSpec
  class ItemModel < Aws::Record::Base
    string_attr :id, hash_key: true
    integer_attr :rk, range_key: true
    string_attr :body, database_attribute_name: "content"
  end

  class CounterModel < Aws::Record::Base
    string_attr :id, hash_key: true
    integer_attr :rk, range_key: true
    atomic_counter :counter
  end
end

# Ported from features/items/items.feature.
describe "Amazon DynamoDB Items", tags: "integration" do
  it "Write an Item with aws-record" do
    integration!
    with_model_table(IntegrationSpec::ItemModel) do |client|
      item = IntegrationSpec::ItemModel.new(id: "1", rk: 1, body: "Hello!")
      item.save!

      stored = client.get_item(
        table_name: IntegrationSpec::ItemModel.table_name,
        key: Aws::DynamoDB::Item{"id" => "1", "rk" => 1_i64},
        consistent_read: true
      ).item
      stored.should eq(Aws::DynamoDB::Item{"id" => "1", "rk" => 1_i64, "content" => "Hello!"})
    end
  end

  it "Read an Item from Amazon DynamoDB with aws-record" do
    integration!
    with_model_table(IntegrationSpec::ItemModel) do |client|
      client.put_item(
        table_name: IntegrationSpec::ItemModel.table_name,
        item: Aws::DynamoDB::Item{"id" => "2", "rk" => 10_i64, "content" => "Aliased column names!"}
      )

      found = IntegrationSpec::ItemModel.find(id: "2", rk: 10).should_not be_nil
      found.id.should eq("2")
      found.rk.should eq(10)
      found.body.should eq("Aliased column names!")
      found.dirty?.should be_false
      found.persisted?.should be_true
    end
  end

  it "Delete an Item from Amazon DynamoDB with aws-record" do
    integration!
    with_model_table(IntegrationSpec::ItemModel) do |client|
      client.put_item(
        table_name: IntegrationSpec::ItemModel.table_name,
        item: Aws::DynamoDB::Item{"id" => "3", "rk" => 5_i64, "content" => "Goodbye!"}
      )

      found = IntegrationSpec::ItemModel.find(id: "3", rk: 5).should_not be_nil
      found.delete!
      found.destroyed?.should be_true

      client.get_item(
        table_name: IntegrationSpec::ItemModel.table_name,
        key: Aws::DynamoDB::Item{"id" => "3", "rk" => 5_i64},
        consistent_read: true
      ).item.should be_nil
    end
  end

  it "Update an Item from Amazon DynamoDB with aws-record" do
    integration!
    with_model_table(IntegrationSpec::ItemModel) do |client|
      client.put_item(
        table_name: IntegrationSpec::ItemModel.table_name,
        item: Aws::DynamoDB::Item{"id" => "4", "rk" => 1_i64, "content" => "Before"}
      )

      found = IntegrationSpec::ItemModel.find(id: "4", rk: 1).should_not be_nil
      found.update(body: "After")

      IntegrationSpec::ItemModel.find_with_opts(key: {id: "4", rk: 1}, consistent_read: true)
        .try(&.body).should eq("After")
    end
  end

  it "Increment Atomic Counter Attribute" do
    integration!
    with_model_table(IntegrationSpec::CounterModel) do
      IntegrationSpec::CounterModel.new(id: "1", rk: 1).save!

      item = IntegrationSpec::CounterModel.find(id: "1", rk: 1).should_not be_nil
      item.counter.should eq(0)

      item.increment_counter!.should eq(1)
      IntegrationSpec::CounterModel.find_with_opts(key: {id: "1", rk: 1}, consistent_read: true)
        .try(&.counter).should eq(1)

      item.increment_counter!(5).should eq(6)
      IntegrationSpec::CounterModel.find_with_opts(key: {id: "1", rk: 1}, consistent_read: true)
        .try(&.counter).should eq(6)
    end
  end
end

# Parity: 5/5 scenarios from features/items/items.feature (aws-record 2.15.1)
