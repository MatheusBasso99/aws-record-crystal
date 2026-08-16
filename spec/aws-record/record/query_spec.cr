require "../../spec_helper"

module QuerySpec
  class TestModel < Aws::Record::Base
    set_table_name "TestTable"
    integer_attr :id, hash_key: true
    date_attr :date, range_key: true
    string_attr :body
  end
end

private def two_items : Aws::DynamoDB::Types::ScanOutput
  Aws::DynamoDB::Types::ScanOutput.new(
    items: [
      Aws::DynamoDB::Item{"id" => 1_i64, "date" => "2016-01-25", "body" => "Item 1"},
      Aws::DynamoDB::Item{"id" => 1_i64, "date" => "2016-01-26", "body" => "Item 2"},
    ],
    count: 2,
    scanned_count: 2
  )
end

private def two_query_items : Aws::DynamoDB::Types::QueryOutput
  Aws::DynamoDB::Types::QueryOutput.new(
    items: [
      Aws::DynamoDB::Item{"id" => 1_i64, "date" => "2016-01-25", "body" => "Item 1"},
      Aws::DynamoDB::Item{"id" => 1_i64, "date" => "2016-01-26", "body" => "Item 2"},
    ],
    count: 2,
    scanned_count: 2
  )
end

describe "Query" do
  describe "#query" do
    it "can pass on a manually constructed query to the client" do
      client = stub_client
      client.stub_responses(:query, two_query_items)
      QuerySpec::TestModel.configure_client(client: client)

      QuerySpec::TestModel.query(
        key_conditions: {
          "id" => Aws::DynamoDB::Types::Condition.new(
            attribute_value_list: [1_i64] of Aws::DynamoDB::Value, comparison_operator: "EQ"
          ),
          "date" => Aws::DynamoDB::Types::Condition.new(
            attribute_value_list: ["2016-01-01"] of Aws::DynamoDB::Value, comparison_operator: "GT"
          ),
        }
      ).to_a

      api_requests(client).map(&.params).should eq([
        JSON.parse(
          %({"TableName":"TestTable","KeyConditions":{) +
          %("id":{"AttributeValueList":[{"N":"1"}],"ComparisonOperator":"EQ"},) +
          %("date":{"AttributeValueList":[{"S":"2016-01-01"}],"ComparisonOperator":"GT"}}})
        ),
      ])
    end
  end

  describe "#scan" do
    it "can pass on a manually constructed scan to the client" do
      client = stub_client
      client.stub_responses(:scan, two_items)
      QuerySpec::TestModel.configure_client(client: client)

      QuerySpec::TestModel.scan.to_a
      api_requests(client).map(&.params).should eq([JSON.parse(%({"TableName":"TestTable"}))])
    end
  end

  describe "#build_query" do
    it "accepts frozen strings as the key expression (#115)" do
      client = stub_client
      QuerySpec::TestModel.configure_client(client: client)

      QuerySpec::TestModel
        .build_query
        .key_expr(":id = ? AND begins_with(date, ?)", "my-id", "2019-07-15")
        .scan_ascending(false)
        .projection_expr(":body")
        .limit(10)
        .complete!
        .to_a

      api_requests(client).map(&.params).should eq([
        JSON.parse(
          %({"TableName":"TestTable","Limit":10,"ScanIndexForward":false,) +
          %("ProjectionExpression":"#BUILDERB",) +
          %("KeyConditionExpression":"#BUILDERA = :buildera AND begins_with(date, :builderb)",) +
          %("ExpressionAttributeNames":{"#BUILDERA":"id","#BUILDERB":"body"},) +
          %("ExpressionAttributeValues":{":buildera":{"S":"my-id"},":builderb":{"S":"2019-07-15"}}})
        ),
      ])
    end

    it "can build and run a query" do
      client = stub_client
      QuerySpec::TestModel.configure_client(client: client)

      QuerySpec::TestModel
        .build_query
        .on_index(:reverse)
        .key_expr(":date = ?", "2019-07-15")
        .scan_ascending(false)
        .projection_expr(":body")
        .limit(10)
        .complete!
        .to_a

      api_requests(client).map(&.params).should eq([
        JSON.parse(
          %({"TableName":"TestTable","IndexName":"reverse","Limit":10,"ScanIndexForward":false,) +
          %("ProjectionExpression":"#BUILDERB","KeyConditionExpression":"#BUILDERA = :buildera",) +
          %("ExpressionAttributeNames":{"#BUILDERA":"date","#BUILDERB":"body"},) +
          %("ExpressionAttributeValues":{":buildera":{"S":"2019-07-15"}}})
        ),
      ])
    end
  end

  describe "#build_scan" do
    it "can build and run a scan" do
      client = stub_client
      QuerySpec::TestModel.configure_client(client: client)

      QuerySpec::TestModel
        .build_scan
        .consistent_read(false)
        .filter_expr(":body = ?", "foo")
        .parallel_scan(total_segments: 5, segment: 2)
        .exclusive_start_key({id: 5, date: "2019-01-01"})
        .complete!
        .to_a

      api_requests(client).map(&.params).should eq([
        JSON.parse(
          %({"TableName":"TestTable","ConsistentRead":false,) +
          %("ExclusiveStartKey":{"id":{"N":"5"},"date":{"S":"2019-01-01"}},) +
          %("TotalSegments":5,"Segment":2,"FilterExpression":"#BUILDERA = :buildera",) +
          %("ExpressionAttributeNames":{"#BUILDERA":"body"},) +
          %("ExpressionAttributeValues":{":buildera":{"S":"foo"}}})
        ),
      ])
    end

    it "does not support key expressions" do
      expect_raises(ArgumentError, "key_expr is only supported for queries.") do
        QuerySpec::TestModel.build_scan.key_expr(":fail = ?", true)
      end
    end

    it "does not support ascending scan settings" do
      expect_raises(ArgumentError, "scan_ascending is only supported for queries.") do
        QuerySpec::TestModel.build_scan.scan_ascending(false)
      end
    end
  end

  describe "BuildableSearch" do
    it "rejects an unsupported operation" do
      expect_raises(ArgumentError, "Unsupported operation: upsert") do
        Aws::Record::BuildableSearch.new(:upsert, QuerySpec::TestModel)
      end
    end

    it "rejects parallel scan settings on a query" do
      expect_raises(ArgumentError, "parallel_scan is only supported for scans") do
        QuerySpec::TestModel.build_query.parallel_scan(total_segments: 2, segment: 0)
      end
    end

    it "raises for an attribute the model does not have" do
      expect_raises(ArgumentError, "No such key nope") do
        QuerySpec::TestModel.build_query.key_expr(":nope = ?", 1)
      end
    end

    it "raises when the substitution set does not match the placeholders" do
      expect_raises(ArgumentError, "Expected 2 values in the substitution set, but found 1") do
        QuerySpec::TestModel.build_query.key_expr(":id = ? AND :body = ?", 1)
      end
    end
  end
end

# Parity: 7/7 examples from spec/aws-record/record/query_spec.rb (aws-record 2.15.1), plus extras.
# The Ruby model also declares a global secondary index, which is only used by `on_index(:reverse)`;
# secondary indexes land in Phase 6.
