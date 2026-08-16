require "../spec_helper"

module IntegrationSpec
  class LocalIndexModel < Aws::Record::Base
    integer_attr :forum_id, hash_key: true
    integer_attr :post_id, range_key: true
    string_attr :forum_name
    string_attr :post_title
    string_attr :post_body
    integer_attr :author_id
    string_attr :author_name

    local_secondary_index :title, range_key: :post_title,
      projection: {projection_type: "INCLUDE", non_key_attributes: ["post_body"]}
  end

  class GlobalIndexModel < Aws::Record::Base
    integer_attr :forum_id, hash_key: true
    integer_attr :post_id, range_key: true
    string_attr :forum_name
    string_attr :post_title
    string_attr :post_body
    integer_attr :author_id
    string_attr :author_name

    global_secondary_index :author, hash_key: :forum_name, range_key: :author_name,
      projection: {projection_type: "ALL"}
  end
end

# Ported from features/indexes/secondary_indexes.feature.
describe "Amazon DynamoDB Secondary Indexes", tags: "integration" do
  it "Create a DynamoDB Table with a Local Secondary Index" do
    integration!
    with_model_table(IntegrationSpec::LocalIndexModel) do |client|
      table = client.describe_table(table_name: IntegrationSpec::LocalIndexModel.table_name)
        .table.should_not be_nil
      indexes = table.local_secondary_indexes.should_not be_nil
      indexes.compact_map(&.index_name).should contain("title")
    end
  end

  it "Create a DynamoDB Table with a Global Secondary Index" do
    integration!
    with_model_table(
      IntegrationSpec::GlobalIndexModel,
      global_secondary_index_throughput: {"author" => DynamoDBLocal.throughput}
    ) do |client|
      table = client.describe_table(table_name: IntegrationSpec::GlobalIndexModel.table_name)
        .table.should_not be_nil
      indexes = table.global_secondary_indexes.should_not be_nil
      indexes.compact_map(&.index_name).should contain("author")
    end
  end
end

# Parity: 2/2 scenarios from features/indexes/secondary_indexes.feature (aws-record 2.15.1)
