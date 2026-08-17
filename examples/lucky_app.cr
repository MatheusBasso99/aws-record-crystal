require "../src/aws-record-crystal"

# The "Using with Lucky/Avram" README section: one file per class in the app.
# Any model may inherit from Aws::Record::Base directly; the shared abstract base is the
# recommended layout when several models should share one client and configuration.

# Stand-in for the `lucky_env` shard, so the config file below type-checks here without Lucky
# installed. In an app the real `LuckyEnv` reads `LUCKY_ENV` (development, test or production).
module LuckyEnv
  def self.environment : String
    ENV["LUCKY_ENV"]? || "development"
  end

  def self.production? : Bool
    environment == "production"
  end

  def self.test? : Bool
    environment == "test"
  end
end

# config/dynamodb.cr — the wiring lives here; the values live in ENV, never in this file.
DYNAMODB =
  if LuckyEnv.production?
    # Required: the app refuses to boot without them (`KeyError: Missing ENV key: "AWS_REGION"`).
    Aws::DynamoDB::Client.new(
      region: ENV["AWS_REGION"],
      credentials: Aws::DynamoDB::Credentials.new(
        access_key_id: ENV["AWS_ACCESS_KEY_ID"],
        secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
        session_token: ENV["AWS_SESSION_TOKEN"]?, # only for temporary credentials
      ),
    )
  elsif LuckyEnv.test?
    # Nothing leaves the process; no credentials needed.
    Aws::DynamoDB::Client.new(stub_responses: true)
  else
    # Development: DynamoDB Local (`docker/docker-compose.yml` starts one) accepts any key pair.
    Aws::DynamoDB::Client.new(
      region: ENV["AWS_REGION"]? || "us-east-1",
      endpoint: ENV["AWS_ENDPOINT_URL_DYNAMODB"]? || "http://localhost:8000",
      credentials: Aws::DynamoDB::Credentials.new(
        access_key_id: ENV["AWS_ACCESS_KEY_ID"]? || "local",
        secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"]? || "local",
      ),
    )
  end

# src/models/dynamo_record.cr — the shared base, the way Avram apps have a `BaseModel`.
# An abstract model with no attributes of its own is allowed; it only carries configuration.
abstract class DynamoRecord < Aws::Record::Base
  configure_client(client: DYNAMODB)
end

# src/models/session.cr — a model file never mentions the client.
class Session < DynamoRecord
  string_attr :sid, hash_key: true
  datetime_attr :created_at
  epoch_time_attr :expires_at
end

# src/models/cart.cr — every other model looks the same.
class Cart < DynamoRecord
  string_attr :user_id, hash_key: true
  list_attr :items
end

Session.dynamodb_client.same?(DYNAMODB) # => true
Cart.dynamodb_client.same?(DYNAMODB)    # => true

# In specs the `LuckyEnv.test?` branch already stubs every model. A model that must talk somewhere
# else is configured directly — before it is first used, because a subclass remembers the client it
# resolved on first use.
Cart.configure_client(client: Aws::DynamoDB::Client.new(stub_responses: true))
