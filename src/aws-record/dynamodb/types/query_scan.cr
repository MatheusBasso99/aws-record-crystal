require "./common"

# The input of `Client#query`.
struct Aws::DynamoDB::Types::QueryInput
  include Shape

  fields(
    table_name : String?,
    index_name : String?,
    select : String?,
    limit : Int32?,
    consistent_read : Bool?,
    scan_index_forward : Bool?,
    exclusive_start_key : Item?,
    projection_expression : String?,
    filter_expression : String?,
    key_condition_expression : String?,
    expression_attribute_names : Hash(String, String)?,
    expression_attribute_values : Item?,
    return_consumed_capacity : String?,
  )
end

# The output of `Client#query`.
struct Aws::DynamoDB::Types::QueryOutput
  include Shape

  fields(
    items : Array(Item)?,
    count : Int32?,
    scanned_count : Int32?,
    last_evaluated_key : Item?,
    consumed_capacity : ConsumedCapacity?,
  )
end

# The input of `Client#scan`.
struct Aws::DynamoDB::Types::ScanInput
  include Shape

  fields(
    table_name : String?,
    index_name : String?,
    select : String?,
    limit : Int32?,
    consistent_read : Bool?,
    exclusive_start_key : Item?,
    total_segments : Int32?,
    segment : Int32?,
    projection_expression : String?,
    filter_expression : String?,
    expression_attribute_names : Hash(String, String)?,
    expression_attribute_values : Item?,
    return_consumed_capacity : String?,
  )
end

# The output of `Client#scan`.
struct Aws::DynamoDB::Types::ScanOutput
  include Shape

  fields(
    items : Array(Item)?,
    count : Int32?,
    scanned_count : Int32?,
    last_evaluated_key : Item?,
    consumed_capacity : ConsumedCapacity?,
  )
end
