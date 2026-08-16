require "../spec_helper"

describe "Aws::DynamoDB::Client against DynamoDB Local", tags: "integration" do
  it "creates a table, writes, reads, queries and deletes" do
    pending! "set AWS_INTEGRATION=1 to run the integration suite" unless DynamoDBLocal.enabled?

    client = DynamoDBLocal.client
    name = DynamoDBLocal.table_name("smoke")

    DynamoDBLocal.with_table(
      client, name,
      attribute_definitions: [
        Aws::DynamoDB::Types::AttributeDefinition.new(attribute_name: "id", attribute_type: "S"),
        Aws::DynamoDB::Types::AttributeDefinition.new(attribute_name: "sort", attribute_type: "N"),
      ],
      key_schema: [
        Aws::DynamoDB::Types::KeySchemaElement.new(attribute_name: "id", key_type: "HASH"),
        Aws::DynamoDB::Types::KeySchemaElement.new(attribute_name: "sort", key_type: "RANGE"),
      ],
      provisioned_throughput: Aws::DynamoDB::Types::ProvisionedThroughput.new(
        read_capacity_units: 5, write_capacity_units: 5
      )
    ) do |table|
      client.describe_table(table_name: table).table.try(&.table_status).should eq("ACTIVE")

      item = Aws::DynamoDB::Item{
        "id"    => "abc",
        "sort"  => 1_i64,
        "body"  => "hello",
        "tags"  => Set{"a", "b"},
        "score" => BigDecimal.new("1.5"),
        "meta"  => Aws::DynamoDB::Item{"nested" => true},
      }
      client.put_item(table_name: table, item: item)

      fetched = client.get_item(
        table_name: table,
        key: Aws::DynamoDB::Item{"id" => "abc", "sort" => 1_i64},
        consistent_read: true
      ).item
      fetched.should eq(item)

      client.update_item(
        table_name: table,
        key: Aws::DynamoDB::Item{"id" => "abc", "sort" => 1_i64},
        update_expression: "SET #B = :b",
        expression_attribute_names: {"#B" => "body"},
        expression_attribute_values: Aws::DynamoDB::Item{":b" => "updated"}
      )

      results = client.query(
        table_name: table,
        key_condition_expression: "#H = :h",
        expression_attribute_names: {"#H" => "id"},
        expression_attribute_values: Aws::DynamoDB::Item{":h" => "abc"},
        consistent_read: true
      )
      results.count.should eq(1)
      results.items.try(&.first["body"]).should eq("updated")

      client.scan(table_name: table).count.should eq(1)

      client.delete_item(table_name: table, key: Aws::DynamoDB::Item{"id" => "abc", "sort" => 1_i64})
      client.get_item(
        table_name: table,
        key: Aws::DynamoDB::Item{"id" => "abc", "sort" => 1_i64},
        consistent_read: true
      ).item.should be_nil
    end

    client.list_tables.table_names.try(&.includes?(name)).should be_false
  end
end
