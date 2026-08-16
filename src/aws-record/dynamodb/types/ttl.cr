require "./common"

# The input of `Client#describe_time_to_live`.
struct Aws::DynamoDB::Types::DescribeTimeToLiveInput
  include Shape

  fields(table_name : String?)
end

# The output of `Client#describe_time_to_live`.
struct Aws::DynamoDB::Types::DescribeTimeToLiveOutput
  include Shape

  fields(time_to_live_description : TimeToLiveDescription?)
end

# The input of `Client#update_time_to_live`.
struct Aws::DynamoDB::Types::UpdateTimeToLiveInput
  include Shape

  fields(
    table_name : String?,
    time_to_live_specification : TimeToLiveSpecification?,
  )
end

# The output of `Client#update_time_to_live`.
struct Aws::DynamoDB::Types::UpdateTimeToLiveOutput
  include Shape

  fields(time_to_live_specification : TimeToLiveSpecification?)
end
