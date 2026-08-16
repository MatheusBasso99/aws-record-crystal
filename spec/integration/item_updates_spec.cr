require "../spec_helper"

module IntegrationSpec
  # The full view of the shared table.
  class SharedFull < Aws::Record::Base
    string_attr :hk, hash_key: true
    string_attr :rk, range_key: true
    string_attr :x
    string_attr :y
    string_attr :z
  end

  # A partial view of the same table, as a single-table-inheritance app would have.
  class SharedPartial < Aws::Record::Base
    string_attr :hk, hash_key: true
    string_attr :rk, range_key: true
    string_attr :x
  end

  class RemovalModel < Aws::Record::Base
    string_attr :hk, hash_key: true
    string_attr :rk, range_key: true
    string_attr :x
    string_attr :y
  end
end

private def with_shared_table(& : Aws::DynamoDB::Client, String ->)
  client = DynamoDBLocal.client
  name = DynamoDBLocal.table_name("shared")
  [IntegrationSpec::SharedFull, IntegrationSpec::SharedPartial].each do |model|
    model.configure_client(client: client)
    model.set_table_name(name)
  end
  migration = Aws::Record::TableMigration.new(IntegrationSpec::SharedFull, client: client)
  migration.create!(provisioned_throughput: DynamoDBLocal.throughput)
  migration.wait_until_available
  client.put_item(
    table_name: name,
    item: Aws::DynamoDB::Item{"hk" => "sample", "rk" => "sample", "x" => "x", "y" => "y", "z" => "z"}
  )
  begin
    yield client, name
  ensure
    delete_table(client, name)
  end
end

# Ported from features/items/item_updates.feature.
describe "Amazon DynamoDB Item Updates", tags: "integration" do
  it "Overwriting an Existing Object With #put_item Fails Without :force" do
    integration!
    with_shared_table do
      item = IntegrationSpec::SharedFull.new(hk: "sample", rk: "sample", x: "foo")
      expect_raises(Aws::Record::Errors::ConditionalWriteFailed) { item.save! }

      found = IntegrationSpec::SharedFull
        .find_with_opts(key: {hk: "sample", rk: "sample"}, consistent_read: true).should_not be_nil
      found.x.should eq("x")
      found.y.should eq("y")
      found.z.should eq("z")
    end
  end

  it "Updating an Object Does Not Clobber Unmodeled Attributes" do
    integration!
    with_shared_table do
      partial = IntegrationSpec::SharedPartial
        .find_with_opts(key: {hk: "sample", rk: "sample"}, consistent_read: true).should_not be_nil
      partial.x = "bar"
      partial.save!

      full = IntegrationSpec::SharedFull
        .find_with_opts(key: {hk: "sample", rk: "sample"}, consistent_read: true).should_not be_nil
      full.x.should eq("bar")
      full.y.should eq("y")
      full.z.should eq("z")
    end
  end

  it "Updating an Object Does Not Clobber Non-Dirty Attributes" do
    integration!
    with_shared_table do
      results = IntegrationSpec::SharedFull.query(
        key_condition_expression: "#H = :h",
        expression_attribute_names: {"#H" => "hk"},
        expression_attribute_values: Aws::DynamoDB::Item{":h" => "sample"},
        consistent_read: true
      )
      item = results.first.as(IntegrationSpec::SharedFull)
      item.y = "foo"
      item.save!

      found = IntegrationSpec::SharedFull
        .find_with_opts(key: {hk: "sample", rk: "sample"}, consistent_read: true).should_not be_nil
      found.x.should eq("x")
      found.y.should eq("foo")
      found.z.should eq("z")
    end
  end

  it "Updating an Object with the Update Model Method" do
    integration!
    with_shared_table do
      IntegrationSpec::SharedFull.update(hk: "sample", rk: "sample", x: "bar")

      found = IntegrationSpec::SharedFull
        .find_with_opts(key: {hk: "sample", rk: "sample"}, consistent_read: true).should_not be_nil
      found.x.should eq("bar")
      found.y.should eq("y")
      found.z.should eq("z")
    end
  end

  it "Updating an Object for Attribute Removal" do
    integration!
    client = DynamoDBLocal.client
    name = DynamoDBLocal.table_name("removal")
    IntegrationSpec::RemovalModel.configure_client(client: client)
    IntegrationSpec::RemovalModel.set_table_name(name)
    migration = Aws::Record::TableMigration.new(IntegrationSpec::RemovalModel, client: client)
    begin
      migration.create!(provisioned_throughput: DynamoDBLocal.throughput)
      migration.wait_until_available
      IntegrationSpec::RemovalModel.new(hk: "sample", rk: "sample", x: "x", y: "y").save!

      IntegrationSpec::RemovalModel.update(hk: "sample", rk: "sample", x: nil)

      stored = client.get_item(
        table_name: name,
        key: Aws::DynamoDB::Item{"hk" => "sample", "rk" => "sample"},
        consistent_read: true
      ).item
      stored.should eq(Aws::DynamoDB::Item{"hk" => "sample", "rk" => "sample", "y" => "y"})
    ensure
      delete_table(client, name)
    end
  end
end

# Parity: 5/5 scenarios from features/items/item_updates.feature (aws-record 2.15.1)
