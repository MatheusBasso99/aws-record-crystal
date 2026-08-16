require "json"
require "./types"

# The DynamoDB operations this client supports.
#
# The enum is what makes `Client#stub_responses(:describe_table, …)` reject a typo at compile time:
# Crystal autocasts the symbol to the matching member, and there is no member to cast to for an
# operation that does not exist.
enum Aws::DynamoDB::Operation
  PutItem
  GetItem
  UpdateItem
  DeleteItem
  Query
  Scan
  BatchGetItem
  BatchWriteItem
  TransactGetItems
  TransactWriteItems
  CreateTable
  UpdateTable
  DeleteTable
  DescribeTable
  ListTables
  DescribeTimeToLive
  UpdateTimeToLive

  # The `X-Amz-Target` header value for this operation.
  def target : String
    "DynamoDB_20120810.#{self}"
  end
end

# One call made through a `Aws::DynamoDB::Client`, as recorded by `Client#api_requests`.
#
# This is the Crystal counterpart of the Ruby gem's `client.handle { |ctx| requests << ctx.params }`
# spec technique, and of `Aws::DynamoDB::Client#api_requests` in the AWS SDK's stub mode.
struct Aws::DynamoDB::ApiCall
  # The operation that was called.
  getter operation : Operation

  # The typed input the operation was called with.
  getter input : Types::Shape

  # The input in DynamoDB's wire form.
  getter params : JSON::Any

  # Records a call to *operation* with *input*.
  def initialize(@operation : Operation, @input : Types::Shape) : Nil
    @params = input.to_wire
  end
end
