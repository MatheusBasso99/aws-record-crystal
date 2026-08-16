require "./shape"

# The typed request and response shapes of the DynamoDB operations this client supports.
#
# Every shape includes `Shape`, so it can be built with keyword arguments, merged with `#merge`
# and rendered with `#to_wire`.
module Aws::DynamoDB::Types
  # An attribute name and its scalar type (`"S"`, `"N"` or `"B"`), as used in a table's key schema.
  struct AttributeDefinition
    include Shape

    fields(
      attribute_name : String?,
      attribute_type : String?,
    )
  end

  # One element of a key schema: an attribute and whether it is the `"HASH"` or `"RANGE"` key.
  struct KeySchemaElement
    include Shape

    fields(
      attribute_name : String?,
      key_type : String?,
    )
  end

  # Provisioned read and write capacity, both as requested and as described by the service.
  struct ProvisionedThroughput
    include Shape

    fields(
      read_capacity_units : Int64?,
      write_capacity_units : Int64?,
      number_of_decreases_today : Int64?,
    )
  end

  # Which attributes an index copies from the table.
  struct Projection
    include Shape

    fields(
      projection_type : String?,
      non_key_attributes : Array(String)?,
    )
  end

  # A local secondary index, both as declared and as described by the service.
  struct LocalSecondaryIndex
    include Shape

    fields(
      index_name : String?,
      key_schema : Array(KeySchemaElement)?,
      projection : Projection?,
      index_arn : String?,
      index_size_bytes : Int64?,
      item_count : Int64?,
    )
  end

  # A global secondary index, both as declared and as described by the service.
  struct GlobalSecondaryIndex
    include Shape

    fields(
      index_name : String?,
      key_schema : Array(KeySchemaElement)?,
      projection : Projection?,
      provisioned_throughput : ProvisionedThroughput?,
      index_status : String?,
      backfilling : Bool?,
      index_arn : String?,
      index_size_bytes : Int64?,
      item_count : Int64?,
    )
  end

  # A comparison used by the legacy `key_conditions`, `query_filter` and `scan_filter` parameters.
  struct Condition
    include Shape

    fields(
      attribute_value_list : Array(Value)?,
      comparison_operator : String?,
    )
  end

  # How a table is billed, as described by the service.
  struct BillingModeSummary
    include Shape

    fields(billing_mode : String?)
  end

  # The service's description of a table.
  struct TableDescription
    include Shape

    fields(
      attribute_definitions : Array(AttributeDefinition)?,
      table_name : String?,
      key_schema : Array(KeySchemaElement)?,
      table_status : String?,
      provisioned_throughput : ProvisionedThroughput?,
      billing_mode_summary : BillingModeSummary?,
      local_secondary_indexes : Array(LocalSecondaryIndex)?,
      global_secondary_indexes : Array(GlobalSecondaryIndex)?,
      item_count : Int64?,
      table_size_bytes : Int64?,
      table_arn : String?,
      table_id : String?,
    )
  end

  # The capacity a request consumed, returned when `return_consumed_capacity` was asked for.
  struct ConsumedCapacity
    include Shape

    fields(
      table_name : String?,
      capacity_units : Float64?,
      read_capacity_units : Float64?,
      write_capacity_units : Float64?,
    )
  end

  # An estimate of the item collection a write touched.
  struct ItemCollectionMetrics
    include Shape

    fields(
      item_collection_key : Item?,
      size_estimate_range_gb : Array(Float64)?,
    )
  end

  # The Time to Live status of a table.
  struct TimeToLiveDescription
    include Shape

    fields(
      time_to_live_status : String?,
      attribute_name : String?,
    )
  end

  # A Time to Live setting to apply to a table.
  struct TimeToLiveSpecification
    include Shape

    fields(
      enabled : Bool?,
      attribute_name : String?,
    )
  end
end
