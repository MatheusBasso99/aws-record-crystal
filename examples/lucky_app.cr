require "../src/aws-record-crystal"

# config/dynamodb.cr — build the client once, at boot.
DYNAMODB = Aws::DynamoDB::Client.new(region: "us-east-1")

# src/models/dynamo_record.cr — the shared base, the way Avram apps have a `BaseModel`.
# An abstract model with no attributes of its own is allowed; it only carries configuration.
abstract class DynamoRecord < Aws::Record::Base
  configure_client(client: DYNAMODB)
end

class Session < DynamoRecord
  string_attr :sid, hash_key: true
  datetime_attr :created_at
  epoch_time_attr :expires_at
end

Session.dynamodb_client.same?(DYNAMODB) # => true
