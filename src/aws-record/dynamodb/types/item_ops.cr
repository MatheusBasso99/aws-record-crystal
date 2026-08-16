require "./common"

# The input of `Client#put_item`.
struct Aws::DynamoDB::Types::PutItemInput
  include Shape

  fields(
    table_name : String?,
    item : Item?,
    condition_expression : String?,
    expression_attribute_names : Hash(String, String)?,
    expression_attribute_values : Item?,
    return_values : String?,
    return_consumed_capacity : String?,
    return_item_collection_metrics : String?,
    return_values_on_condition_check_failure : String?,
  )
end

# The output of `Client#put_item`.
struct Aws::DynamoDB::Types::PutItemOutput
  include Shape

  fields(
    attributes : Item?,
    consumed_capacity : ConsumedCapacity?,
    item_collection_metrics : ItemCollectionMetrics?,
  )
end

# The input of `Client#get_item`.
struct Aws::DynamoDB::Types::GetItemInput
  include Shape

  fields(
    table_name : String?,
    key : Item?,
    attributes_to_get : Array(String)?,
    consistent_read : Bool?,
    projection_expression : String?,
    expression_attribute_names : Hash(String, String)?,
    return_consumed_capacity : String?,
  )
end

# The output of `Client#get_item`.
struct Aws::DynamoDB::Types::GetItemOutput
  include Shape

  fields(
    item : Item?,
    consumed_capacity : ConsumedCapacity?,
  )
end

# The input of `Client#update_item`.
struct Aws::DynamoDB::Types::UpdateItemInput
  include Shape

  fields(
    table_name : String?,
    key : Item?,
    update_expression : String?,
    condition_expression : String?,
    expression_attribute_names : Hash(String, String)?,
    expression_attribute_values : Item?,
    return_values : String?,
    return_consumed_capacity : String?,
    return_item_collection_metrics : String?,
    return_values_on_condition_check_failure : String?,
  )
end

# The output of `Client#update_item`.
struct Aws::DynamoDB::Types::UpdateItemOutput
  include Shape

  fields(
    attributes : Item?,
    consumed_capacity : ConsumedCapacity?,
    item_collection_metrics : ItemCollectionMetrics?,
  )
end

# The input of `Client#delete_item`.
struct Aws::DynamoDB::Types::DeleteItemInput
  include Shape

  fields(
    table_name : String?,
    key : Item?,
    condition_expression : String?,
    expression_attribute_names : Hash(String, String)?,
    expression_attribute_values : Item?,
    return_values : String?,
    return_consumed_capacity : String?,
    return_item_collection_metrics : String?,
    return_values_on_condition_check_failure : String?,
  )
end

# The output of `Client#delete_item`.
struct Aws::DynamoDB::Types::DeleteItemOutput
  include Shape

  fields(
    attributes : Item?,
    consumed_capacity : ConsumedCapacity?,
    item_collection_metrics : ItemCollectionMetrics?,
  )
end
