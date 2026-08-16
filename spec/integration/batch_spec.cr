require "../spec_helper"

module IntegrationSpec
  class BatchParent < Aws::Record::Base
    integer_attr :id, hash_key: true, database_attribute_name: "Food ID"
    string_attr :dish, range_key: true
    boolean_attr :spicy
  end

  class BatchChild < BatchParent
    boolean_attr :gluten_free
  end
end

# Ported from features/batch/batch.feature.
describe "Amazon DynamoDB Batch", tags: "integration" do
  it "Perform a batch set of writes and read" do
    integration!
    client = DynamoDBLocal.client
    parent_table = DynamoDBLocal.table_name("FoodTable")
    child_table = DynamoDBLocal.table_name("DessertTable")
    IntegrationSpec::BatchParent.configure_client(client: client)
    IntegrationSpec::BatchParent.set_table_name(parent_table)
    IntegrationSpec::BatchChild.configure_client(client: client)
    IntegrationSpec::BatchChild.set_table_name(child_table)

    begin
      [IntegrationSpec::BatchParent, IntegrationSpec::BatchChild].each do |model|
        migration = Aws::Record::TableMigration.new(model, client: client)
        migration.create!(provisioned_throughput: DynamoDBLocal.throughput(2_i64, 2_i64))
        migration.wait_until_available
      end

      Aws::Record::Batch.write(client: client) do |db|
        db.put(IntegrationSpec::BatchParent.new(id: 1, dish: "Papaya Salad", spicy: true))
        db.put(IntegrationSpec::BatchParent.new(id: 2, dish: "Hamburger", spicy: false))
        db.put(IntegrationSpec::BatchChild.new(id: 1, dish: "Apple Pie", spicy: false, gluten_free: false))
      end.complete?.should be_true

      results = Aws::Record::Batch.read(client: client) do |db|
        db.find(IntegrationSpec::BatchParent, id: 1, dish: "Papaya Salad")
        db.find(IntegrationSpec::BatchParent, id: 2, dish: "Hamburger")
        db.find(IntegrationSpec::BatchChild, id: 1, dish: "Apple Pie")
      end

      results.complete?.should be_true
      dishes = results.map { |item| item.as(IntegrationSpec::BatchParent).dish }.to_a
      dishes.compact.sort!.should eq(["Apple Pie", "Hamburger", "Papaya Salad"])

      pie = results.find { |item| item.as(IntegrationSpec::BatchParent).dish == "Apple Pie" }
        .should_not be_nil
      pie.should be_a(IntegrationSpec::BatchChild)
      pie.as(IntegrationSpec::BatchChild).gluten_free.should be_false
    ensure
      delete_table(client, parent_table)
      delete_table(client, child_table)
    end
  end
end

# Parity: 1/1 scenario from features/batch/batch.feature (aws-record 2.15.1)
