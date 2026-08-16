require "../spec_helper"

module IntegrationSpec
  class TableModel < Aws::Record::Base
    string_attr :id, hash_key: true
    integer_attr :count
  end
end

# Ported from features/migrations/tables.feature.
describe "Amazon DynamoDB Tables", tags: "integration" do
  it "Create a DynamoDB Table with aws-record" do
    integration!
    with_model_table(IntegrationSpec::TableModel) do
      IntegrationSpec::TableModel.table_exists?.should be_true
    end
  end

  it "Delete a DynamoDB Table After Creation" do
    integration!
    client = DynamoDBLocal.client
    IntegrationSpec::TableModel.configure_client(client: client)
    IntegrationSpec::TableModel.set_table_name(DynamoDBLocal.table_name("tables_delete"))
    migration = Aws::Record::TableMigration.new(IntegrationSpec::TableModel, client: client)
    migration.create!(provisioned_throughput: DynamoDBLocal.throughput)
    migration.wait_until_available
    IntegrationSpec::TableModel.table_exists?.should be_true

    migration.delete!
    client.wait_until_table_not_exists(
      IntegrationSpec::TableModel.table_name, delay: 200.milliseconds, max_attempts: 50
    )
    IntegrationSpec::TableModel.table_exists?.should be_false
  end

  it "Provide a Migration Waiter" do
    integration!
    client = DynamoDBLocal.client
    IntegrationSpec::TableModel.configure_client(client: client)
    IntegrationSpec::TableModel.set_table_name(DynamoDBLocal.table_name("tables_waiter"))
    migration = Aws::Record::TableMigration.new(IntegrationSpec::TableModel, client: client)
    begin
      migration.create!(provisioned_throughput: DynamoDBLocal.throughput)
      migration.wait_until_available.table_status.should eq("ACTIVE")
      IntegrationSpec::TableModel.table_exists?.should be_true
    ensure
      delete_table(client, IntegrationSpec::TableModel.table_name)
    end
  end

  it "Update a Table After Creation" do
    integration!
    with_model_table(IntegrationSpec::TableModel) do
      IntegrationSpec::TableModel.provisioned_throughput
        .should eq({read_capacity_units: 1_i64, write_capacity_units: 1_i64})

      migration = Aws::Record::TableMigration.new(
        IntegrationSpec::TableModel, client: IntegrationSpec::TableModel.dynamodb_client
      )
      migration.update!(provisioned_throughput: DynamoDBLocal.throughput(2_i64, 2_i64))

      IntegrationSpec::TableModel.provisioned_throughput
        .should eq({read_capacity_units: 2_i64, write_capacity_units: 2_i64})
    end
  end
end

# Parity: 4/4 scenarios from features/migrations/tables.feature (aws-record 2.15.1)
