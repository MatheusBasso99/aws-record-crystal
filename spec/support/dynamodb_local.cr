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

  # Runs the block with a table that is deleted afterwards, whatever happens.
  def with_table(client : Aws::DynamoDB::Client, name : String, **create_opts, &)
    client.create_table(**{table_name: name}.merge(create_opts))
    client.wait_until_table_exists(name, delay: 200.milliseconds, max_attempts: 50)
    begin
      yield name
    ensure
      client.delete_table(table_name: name)
    end
  end
end
