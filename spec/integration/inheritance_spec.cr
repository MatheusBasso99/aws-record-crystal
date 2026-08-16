require "../spec_helper"

module IntegrationSpec
  # The feature's Parent model, shared by both scenarios.
  class Animal < Aws::Record::Base
    set_table_name "Animal"
    integer_attr :id, hash_key: true
    string_attr :name, range_key: true
    string_attr :size
    list_attr :characteristics

    global_secondary_index :gsi, hash_key: :id, range_key: :size,
      projection: {projection_type: "ALL"}
  end

  # A Child model that shares the Parent's table.
  class Dog < Animal
    boolean_attr :family_friendly
  end

  # A Child model with a table of its own.
  class Cat < Animal
    set_table_name "Cat"
    integer_attr :toe_beans
  end
end

private def animal_config(model : Aws::Record::Base.class) : Aws::Record::TableConfig
  local_table_config(model) do |table|
    table.read_capacity_units(2)
    table.write_capacity_units(2)
    table.global_secondary_index(:gsi) do |index|
      index.read_capacity_units(1)
      index.write_capacity_units(1)
    end
  end
end

# Ported from features/inheritance/inheritance.feature.
describe "Amazon DynamoDB Inheritance", tags: "integration" do
  it "Create a Table and be able to create Items from both Child model and Parent model" do
    integration!
    client = DynamoDBLocal.client
    name = DynamoDBLocal.table_name("Animal")
    IntegrationSpec::Animal.configure_client(client: client)
    IntegrationSpec::Animal.set_table_name(name)
    IntegrationSpec::Dog.configure_client(client: client)
    # The child has no table name of its own, so it shares the parent's.
    IntegrationSpec::Dog.table_name.should eq(name)

    begin
      animal_config(IntegrationSpec::Dog).migrate!
      table = client.describe_table(table_name: name).table.should_not be_nil
      table.table_status.should eq("ACTIVE")
      indexes = table.global_secondary_indexes.should_not be_nil
      indexes.compact_map(&.index_name).should contain("gsi")

      dog = IntegrationSpec::Dog.new(
        id: 1, name: "Cheeseburger", size: "Large",
        characteristics: ["Friendly", "Curious", "Loves kisses"], family_friendly: true
      )
      dog.save!

      found_dog = IntegrationSpec::Dog.find(id: 1, name: "Cheeseburger").should_not be_nil
      found_dog.id.should eq(1)
      found_dog.name.should eq("Cheeseburger")
      found_dog.size.should eq("Large")
      found_dog.characteristics.should eq(["Friendly", "Curious", "Loves kisses"])
      found_dog.family_friendly.should be_true

      animal = IntegrationSpec::Animal.new(
        id: 2, name: "Applejack", size: "Medium", characteristics: ["Aloof", "Dignified"]
      )
      animal.save!

      found_animal = IntegrationSpec::Animal.find(id: 2, name: "Applejack").should_not be_nil
      found_animal.id.should eq(2)
      found_animal.name.should eq("Applejack")
      found_animal.size.should eq("Medium")
      found_animal.characteristics.should eq(["Aloof", "Dignified"])
    ensure
      delete_table(client, name)
    end
  end

  it "Create a Table based on the Child Model and be able to create an item" do
    integration!
    client = DynamoDBLocal.client
    name = DynamoDBLocal.table_name("Cat")
    IntegrationSpec::Animal.configure_client(client: client)
    IntegrationSpec::Cat.configure_client(client: client)
    IntegrationSpec::Cat.set_table_name(name)

    begin
      animal_config(IntegrationSpec::Cat).migrate!
      client.describe_table(table_name: name).table.try(&.table_status).should eq("ACTIVE")

      cat = IntegrationSpec::Cat.new(
        id: 1, name: "Donut", size: "Chonk",
        characteristics: ["Makes good bread", "Likes snacks"], toe_beans: 9
      )
      cat.save!

      found = IntegrationSpec::Cat.find(id: 1, name: "Donut").should_not be_nil
      found.id.should eq(1)
      found.name.should eq("Donut")
      found.size.should eq("Chonk")
      found.characteristics.should eq(["Makes good bread", "Likes snacks"])
      found.toe_beans.should eq(9)
    ensure
      delete_table(client, name)
    end
  end
end

# Parity: 2/2 scenarios from features/inheritance/inheritance.feature (aws-record 2.15.1)
