require "../src/aws-record-crystal"

# The "Using with Lucky/Avram" README section: one file per class in the app.
# Any model may inherit from Aws::Record::Base directly; the shared abstract base is the
# recommended layout when several models should share one client and configuration.

# config/dynamodb.cr — build the client once, at boot.
DYNAMODB = Aws::DynamoDB::Client.new(region: "us-east-1")

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

# spec/spec_helper.cr — before any model is used, point them all at a stub.
STUB = Aws::DynamoDB::Client.new(stub_responses: true)
DynamoRecord.configure_client(client: STUB)
