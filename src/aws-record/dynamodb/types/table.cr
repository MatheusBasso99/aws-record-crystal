require "./common"

# A global secondary index to add to a table.
struct Aws::DynamoDB::Types::CreateGlobalSecondaryIndexAction
  include Shape

  fields(
    index_name : String?,
    key_schema : Array(KeySchemaElement)?,
    projection : Projection?,
    provisioned_throughput : ProvisionedThroughput?,
  )
end

# A change to the provisioned throughput of an existing global secondary index.
struct Aws::DynamoDB::Types::UpdateGlobalSecondaryIndexAction
  include Shape

  fields(
    index_name : String?,
    provisioned_throughput : ProvisionedThroughput?,
  )
end

# A global secondary index to remove from a table.
struct Aws::DynamoDB::Types::DeleteGlobalSecondaryIndexAction
  include Shape

  fields(index_name : String?)
end

# One global secondary index change of an `UpdateTable` request.
struct Aws::DynamoDB::Types::GlobalSecondaryIndexUpdate
  include Shape

  fields(
    create : CreateGlobalSecondaryIndexAction?,
    update : UpdateGlobalSecondaryIndexAction?,
    delete : DeleteGlobalSecondaryIndexAction?,
  )
end

# The input of `Client#create_table`.
struct Aws::DynamoDB::Types::CreateTableInput
  include Shape

  fields(
    table_name : String?,
    attribute_definitions : Array(AttributeDefinition)?,
    key_schema : Array(KeySchemaElement)?,
    local_secondary_indexes : Array(LocalSecondaryIndex)?,
    global_secondary_indexes : Array(GlobalSecondaryIndex)?,
    billing_mode : String?,
    provisioned_throughput : ProvisionedThroughput?,
  )
end

# The output of `Client#create_table`.
struct Aws::DynamoDB::Types::CreateTableOutput
  include Shape

  fields(table_description : TableDescription?)
end

# The input of `Client#update_table`.
struct Aws::DynamoDB::Types::UpdateTableInput
  include Shape

  fields(
    table_name : String?,
    attribute_definitions : Array(AttributeDefinition)?,
    billing_mode : String?,
    provisioned_throughput : ProvisionedThroughput?,
    global_secondary_index_updates : Array(GlobalSecondaryIndexUpdate)?,
  )
end

# The output of `Client#update_table`.
struct Aws::DynamoDB::Types::UpdateTableOutput
  include Shape

  fields(table_description : TableDescription?)
end

# The input of `Client#delete_table`.
struct Aws::DynamoDB::Types::DeleteTableInput
  include Shape

  fields(table_name : String?)
end

# The output of `Client#delete_table`.
struct Aws::DynamoDB::Types::DeleteTableOutput
  include Shape

  fields(table_description : TableDescription?)
end

# The input of `Client#describe_table`.
struct Aws::DynamoDB::Types::DescribeTableInput
  include Shape

  fields(table_name : String?)
end

# The output of `Client#describe_table`.
struct Aws::DynamoDB::Types::DescribeTableOutput
  include Shape

  fields(table : TableDescription?)
end

# The input of `Client#list_tables`.
struct Aws::DynamoDB::Types::ListTablesInput
  include Shape

  fields(
    exclusive_start_table_name : String?,
    limit : Int32?,
  )
end

# The output of `Client#list_tables`.
struct Aws::DynamoDB::Types::ListTablesOutput
  include Shape

  fields(
    table_names : Array(String)?,
    last_evaluated_table_name : String?,
  )
end
