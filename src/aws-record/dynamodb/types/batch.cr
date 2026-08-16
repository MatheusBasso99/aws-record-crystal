require "./common"

# The keys and read options of one table in a `BatchGetItem` request.
struct Aws::DynamoDB::Types::KeysAndAttributes
  include Shape

  fields(
    keys : Array(Item)?,
    attributes_to_get : Array(String)?,
    consistent_read : Bool?,
    projection_expression : String?,
    expression_attribute_names : Hash(String, String)?,
  )
end

# The item of a `BatchWriteItem` put request.
struct Aws::DynamoDB::Types::PutRequest
  include Shape

  fields(item : Item?)
end

# The key of a `BatchWriteItem` delete request.
struct Aws::DynamoDB::Types::DeleteRequest
  include Shape

  fields(key : Item?)
end

# One write of a `BatchWriteItem` request: either a put or a delete.
struct Aws::DynamoDB::Types::WriteRequest
  include Shape

  fields(
    put_request : PutRequest?,
    delete_request : DeleteRequest?,
  )
end

# The input of `Client#batch_get_item`.
struct Aws::DynamoDB::Types::BatchGetItemInput
  include Shape

  fields(
    request_items : Hash(String, KeysAndAttributes)?,
    return_consumed_capacity : String?,
  )
end

# The output of `Client#batch_get_item`.
struct Aws::DynamoDB::Types::BatchGetItemOutput
  include Shape

  fields(
    responses : Hash(String, Array(Item))?,
    unprocessed_keys : Hash(String, KeysAndAttributes)?,
    consumed_capacity : Array(ConsumedCapacity)?,
  )
end

# The input of `Client#batch_write_item`.
struct Aws::DynamoDB::Types::BatchWriteItemInput
  include Shape

  fields(
    request_items : Hash(String, Array(WriteRequest))?,
    return_consumed_capacity : String?,
    return_item_collection_metrics : String?,
  )
end

# The output of `Client#batch_write_item`.
struct Aws::DynamoDB::Types::BatchWriteItemOutput
  include Shape

  fields(
    unprocessed_items : Hash(String, Array(WriteRequest))?,
    item_collection_metrics : Hash(String, Array(ItemCollectionMetrics))?,
    consumed_capacity : Array(ConsumedCapacity)?,
  )
end
