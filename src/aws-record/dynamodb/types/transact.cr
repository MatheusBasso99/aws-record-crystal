require "./common"

# One item to read in a `TransactGetItems` request.
struct Aws::DynamoDB::Types::Get
  include Shape

  fields(
    table_name : String?,
    key : Item?,
    projection_expression : String?,
    expression_attribute_names : Hash(String, String)?,
  )
end

# One element of a `TransactGetItems` request.
struct Aws::DynamoDB::Types::TransactGetItem
  include Shape

  fields(get : Get?)
end

# One element of a `TransactGetItems` response; `#item` is `nil` when the item does not exist.
struct Aws::DynamoDB::Types::ItemResponse
  include Shape

  fields(item : Item?)
end

# A condition to evaluate — without writing anything — as part of a transactional write.
struct Aws::DynamoDB::Types::ConditionCheck
  include Shape

  fields(
    table_name : String?,
    key : Item?,
    condition_expression : String?,
    expression_attribute_names : Hash(String, String)?,
    expression_attribute_values : Item?,
    return_values_on_condition_check_failure : String?,
  )
end

# A put to perform as part of a transactional write.
struct Aws::DynamoDB::Types::Put
  include Shape

  fields(
    table_name : String?,
    item : Item?,
    condition_expression : String?,
    expression_attribute_names : Hash(String, String)?,
    expression_attribute_values : Item?,
    return_values_on_condition_check_failure : String?,
  )
end

# A delete to perform as part of a transactional write.
struct Aws::DynamoDB::Types::Delete
  include Shape

  fields(
    table_name : String?,
    key : Item?,
    condition_expression : String?,
    expression_attribute_names : Hash(String, String)?,
    expression_attribute_values : Item?,
    return_values_on_condition_check_failure : String?,
  )
end

# An update to perform as part of a transactional write.
struct Aws::DynamoDB::Types::Update
  include Shape

  fields(
    table_name : String?,
    key : Item?,
    update_expression : String?,
    condition_expression : String?,
    expression_attribute_names : Hash(String, String)?,
    expression_attribute_values : Item?,
    return_values_on_condition_check_failure : String?,
  )
end

# One element of a `TransactWriteItems` request; exactly one of its members is set.
struct Aws::DynamoDB::Types::TransactWriteItem
  include Shape

  fields(
    condition_check : ConditionCheck?,
    put : Put?,
    delete : Delete?,
    update : Update?,
  )
end

# The input of `Client#transact_get_items`.
struct Aws::DynamoDB::Types::TransactGetItemsInput
  include Shape

  fields(
    transact_items : Array(TransactGetItem)?,
    return_consumed_capacity : String?,
  )
end

# The output of `Client#transact_get_items`.
struct Aws::DynamoDB::Types::TransactGetItemsOutput
  include Shape

  fields(
    responses : Array(ItemResponse)?,
    consumed_capacity : Array(ConsumedCapacity)?,
  )
end

# The input of `Client#transact_write_items`.
struct Aws::DynamoDB::Types::TransactWriteItemsInput
  include Shape

  fields(
    transact_items : Array(TransactWriteItem)?,
    client_request_token : String?,
    return_consumed_capacity : String?,
    return_item_collection_metrics : String?,
  )
end

# The output of `Client#transact_write_items`.
struct Aws::DynamoDB::Types::TransactWriteItemsOutput
  include Shape

  fields(
    consumed_capacity : Array(ConsumedCapacity)?,
    item_collection_metrics : Hash(String, Array(ItemCollectionMetrics))?,
  )
end
