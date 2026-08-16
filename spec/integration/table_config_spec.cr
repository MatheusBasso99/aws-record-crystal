require "../spec_helper"

module IntegrationSpec
  class ConfigModel < Aws::Record::Base
    string_attr :id, hash_key: true
    integer_attr :count, range_key: true
  end

  # Crystal declares indexes at compile time, so the "add a global secondary index to the model"
  # step is two models over one table: the table starts out as this one...
  class ConfigNoIndexModel < Aws::Record::Base
    string_attr :id, hash_key: true
    integer_attr :count, range_key: true
    string_attr :gsi_range
  end

  # ...and the configuration that adds the index is written against this one.
  class ConfigIndexedModel < Aws::Record::Base
    string_attr :id, hash_key: true
    integer_attr :count, range_key: true
    string_attr :gsi_range

    global_secondary_index :gsi, hash_key: :id, range_key: :gsi_range,
      projection: {projection_type: "ALL"}
  end

  class ConfigTtlModel < Aws::Record::Base
    string_attr :id, hash_key: true
    integer_attr :count, range_key: true
    epoch_time_attr :ttl
  end
end

private def provisioned_config(model : Aws::Record::Base.class) : Aws::Record::TableConfig
  local_table_config(model) do |table|
    table.read_capacity_units(2)
    table.write_capacity_units(2)
  end
end

private def indexed_config(model : Aws::Record::Base.class) : Aws::Record::TableConfig
  local_table_config(model) do |table|
    table.read_capacity_units(2)
    table.write_capacity_units(2)
    table.global_secondary_index(:gsi) do |index|
      index.read_capacity_units(1)
      index.write_capacity_units(1)
    end
  end
end

private def ppr_config(model : Aws::Record::Base.class) : Aws::Record::TableConfig
  local_table_config(model, &.billing_mode("PAY_PER_REQUEST"))
end

private def table_should_exist(client : Aws::DynamoDB::Client, name : String) : Nil
  client.describe_table(table_name: name).table.try(&.table_status).should eq("ACTIVE")
end

private def create_table_for(model : Aws::Record::Base.class, read : Int64, write : Int64) : Nil
  migration = Aws::Record::TableMigration.new(model, client: DynamoDBLocal.client)
  migration.create!(provisioned_throughput: DynamoDBLocal.throughput(read, write))
  migration.wait_until_available
end

# The models that share one table for the "add a global secondary index" scenarios.
private def with_shared_config_table(& : Aws::DynamoDB::Client, String ->)
  client = DynamoDBLocal.client
  name = DynamoDBLocal.table_name("TableConfig")
  [IntegrationSpec::ConfigNoIndexModel, IntegrationSpec::ConfigIndexedModel].each do |model|
    model.configure_client(client: client)
    model.set_table_name(name)
  end
  begin
    yield client, name
  ensure
    delete_table(client, name)
  end
end

# Ported from features/table_config/table_config.feature.
describe Aws::Record::TableConfig, tags: "integration" do
  it "Create a New Table With TableConfig" do
    integration!
    with_model_config(IntegrationSpec::ConfigModel) do |client, name|
      config = provisioned_config(IntegrationSpec::ConfigModel)
      config.migrate!

      table_should_exist(client, name)
      config.compatible?.should be_true
      config.exact_match?.should be_true
    end
  end

  it "Update an Existing Table With TableConfig" do
    integration!
    with_model_config(IntegrationSpec::ConfigModel) do |client, name|
      config = provisioned_config(IntegrationSpec::ConfigModel)
      create_table_for(IntegrationSpec::ConfigModel, 1_i64, 1_i64)

      table_should_exist(client, name)
      config.compatible?.should be_false

      config.migrate!
      config.compatible?.should be_true
    end
  end

  it "Create a New Table With Global Secondary Indexes" do
    integration!
    with_model_config(IntegrationSpec::ConfigIndexedModel) do
      config = indexed_config(IntegrationSpec::ConfigIndexedModel)
      config.migrate!

      config.compatible?.should be_true
      config.exact_match?.should be_true
    end
  end

  it "Update a Table to Add Global Secondary Indexes" do
    integration!
    with_shared_config_table do |client, name|
      create_table_for(IntegrationSpec::ConfigNoIndexModel, 1_i64, 1_i64)
      table_should_exist(client, name)

      config = indexed_config(IntegrationSpec::ConfigIndexedModel)
      config.compatible?.should be_false

      config.migrate!
      config.compatible?.should be_true
      config.exact_match?.should be_true
    end
  end

  it "Create a New Table With TTL" do
    integration!
    with_model_config(IntegrationSpec::ConfigTtlModel) do |client, name|
      config = local_table_config(IntegrationSpec::ConfigTtlModel) do |table|
        table.read_capacity_units(2)
        table.write_capacity_units(2)
        table.ttl_attribute(:ttl)
      end
      config.migrate!

      table_should_exist(client, name)
      config.compatible?.should be_true
      config.exact_match?.should be_true
    end
  end

  it "Update an Existing Table With TTL" do
    integration!
    with_model_config(IntegrationSpec::ConfigTtlModel) do |client, name|
      config = local_table_config(IntegrationSpec::ConfigTtlModel) do |table|
        table.read_capacity_units(2)
        table.write_capacity_units(2)
        table.ttl_attribute(:ttl)
      end
      create_table_for(IntegrationSpec::ConfigTtlModel, 2_i64, 2_i64)

      table_should_exist(client, name)
      config.compatible?.should be_false

      config.migrate!
      config.compatible?.should be_true
      config.exact_match?.should be_true
    end
  end

  it "Create a New Table With PPR Billing" do
    integration!
    with_model_config(IntegrationSpec::ConfigModel) do |client, name|
      config = ppr_config(IntegrationSpec::ConfigModel)
      config.migrate!

      table_should_exist(client, name)
      config.compatible?.should be_true
      config.exact_match?.should be_true
    end
  end

  it "Transition from PPR Billing to Provisioned" do
    integration!
    with_model_config(IntegrationSpec::ConfigModel) do |client, name|
      ppr = ppr_config(IntegrationSpec::ConfigModel)
      ppr.migrate!
      table_should_exist(client, name)
      ppr.exact_match?.should be_true

      provisioned = provisioned_config(IntegrationSpec::ConfigModel)
      provisioned.compatible?.should be_false

      provisioned.migrate!
      provisioned.compatible?.should be_true
      provisioned.exact_match?.should be_true
    end
  end

  it "Transition from Provisioned Billing to PPR" do
    integration!
    with_model_config(IntegrationSpec::ConfigModel) do |client, name|
      provisioned = provisioned_config(IntegrationSpec::ConfigModel)
      provisioned.migrate!
      table_should_exist(client, name)
      provisioned.exact_match?.should be_true

      ppr = ppr_config(IntegrationSpec::ConfigModel)
      ppr.compatible?.should be_false

      ppr.migrate!
      ppr.compatible?.should be_true
      ppr.exact_match?.should be_true
    end
  end

  it "Create a New Table With Global Secondary Indexes and PPR" do
    integration!
    with_model_config(IntegrationSpec::ConfigIndexedModel) do
      config = ppr_config(IntegrationSpec::ConfigIndexedModel)
      config.migrate!

      config.compatible?.should be_true
      config.exact_match?.should be_true
    end
  end

  it "Update a PPR Table to Add Global Secondary Indexes" do
    integration!
    with_shared_config_table do
      plain = ppr_config(IntegrationSpec::ConfigNoIndexModel)
      plain.migrate!
      plain.compatible?.should be_true
      plain.exact_match?.should be_true

      indexed = ppr_config(IntegrationSpec::ConfigIndexedModel)
      indexed.compatible?.should be_false

      indexed.migrate!
      indexed.compatible?.should be_true
      indexed.exact_match?.should be_true
    end
  end
end

# Parity: 11/11 scenarios from features/table_config/table_config.feature (aws-record 2.15.1)
