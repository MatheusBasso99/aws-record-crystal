require "uuid"

# Helpers for the specs that run against a real DynamoDB Local (`scripts/integration.sh`).
#
# They are tagged `integration` and skipped by `scripts/check.sh`; `AWS_INTEGRATION=1` and
# `DYNAMODB_ENDPOINT` select and point them at the container.
module DynamoDBLocal
  extend self

  # Whether the integration suite was asked for.
  def enabled? : Bool
    ENV["AWS_INTEGRATION"]? == "1"
  end

  # The endpoint DynamoDB Local listens on.
  def endpoint : String
    ENV["DYNAMODB_ENDPOINT"]? || "http://localhost:8000"
  end

  # A client pointed at DynamoDB Local. Any credentials are accepted by the container.
  def client : Aws::DynamoDB::Client
    Aws::DynamoDB::Client.new(
      region: ENV["AWS_REGION"]? || "us-east-1",
      endpoint: endpoint,
      credentials: Aws::DynamoDB::Credentials.new(
        ENV["AWS_ACCESS_KEY_ID"]? || "local",
        ENV["AWS_SECRET_ACCESS_KEY"]? || "local"
      )
    )
  end

  # A table name no other run will use.
  def table_name(prefix : String) : String
    "#{prefix}_#{UUID.random}"
  end

  # Provisioned throughput of one read and one write unit, which is all these specs need.
  def throughput(read : Int64 = 1_i64, write : Int64 = 1_i64) : Aws::DynamoDB::Types::ProvisionedThroughput
    Aws::DynamoDB::Types::ProvisionedThroughput.new(read_capacity_units: read, write_capacity_units: write)
  end
end

# Marks the example pending unless the integration suite was asked for.
def integration! : Nil
  return if DynamoDBLocal.enabled?
  pending!("set AWS_INTEGRATION=1 and run scripts/integration.sh")
end

# Points *model* at a fresh table, creates it with `TableMigration`, and drops it afterwards.
#
# Crystal models are static, so the table name is set at run time to keep concurrent runs apart.
def with_model_table(model : Aws::Record::Base.class, **create_opts, & : Aws::DynamoDB::Client ->)
  client = DynamoDBLocal.client
  model.configure_client(client: client)
  model.set_table_name(DynamoDBLocal.table_name(model.name.split("::").last))
  migration = Aws::Record::TableMigration.new(model, client: client)
  migration.create!(**{provisioned_throughput: DynamoDBLocal.throughput}.merge(create_opts))
  migration.wait_until_available
  begin
    yield client
  ensure
    delete_table(client, model.table_name)
  end
end

# Points *model* at a fresh table and yields a `TableConfig` builder for it, dropping it afterwards.
def with_model_config(model : Aws::Record::Base.class, & : Aws::DynamoDB::Client, String ->)
  client = DynamoDBLocal.client
  model.configure_client(client: client)
  name = DynamoDBLocal.table_name(model.name.split("::").last)
  model.set_table_name(name)
  begin
    yield client, name
  ensure
    delete_table(client, name)
  end
end

# Deletes *name*, ignoring a table that is already gone.
def delete_table(client : Aws::DynamoDB::Client, name : String) : Nil
  client.delete_table(table_name: name)
rescue Aws::DynamoDB::Errors::ResourceNotFoundException
  # already gone
end

# A `TableConfig` for *model* pointed at DynamoDB Local.
def local_table_config(model : Aws::Record::Base.class, & : Aws::Record::TableConfig ->) : Aws::Record::TableConfig
  Aws::Record::TableConfig.define do |table|
    table.model_class model
    yield table
    table.client_options(DynamoDBLocal.client)
  end
end
