require "../../spec_helper"

describe Aws::DynamoDB::Types do
  describe "Shape" do
    it "maps field names to PascalCase wire keys" do
      input = Aws::DynamoDB::Types::ScanInput.new(table_name: "T", total_segments: 4, segment: 1)
      input.to_wire.to_json.should eq(%({"TableName":"T","TotalSegments":4,"Segment":1}))
    end

    it "leaves unset fields out of the wire form" do
      Aws::DynamoDB::Types::DescribeTableInput.new(table_name: "T").to_wire.to_json.should eq(%({"TableName":"T"}))
      Aws::DynamoDB::Types::DescribeTableInput.new.to_wire.to_json.should eq("{}")
    end

    it "marshals item valued fields as attribute values" do
      input = Aws::DynamoDB::Types::PutItemInput.new(
        table_name: "T",
        item: Aws::DynamoDB::Item{"id" => 1_i64, "name" => "x", "tags" => Set{"a"}}
      )
      input.to_wire.to_json.should eq(
        %({"TableName":"T","Item":{"id":{"N":"1"},"name":{"S":"x"},"tags":{"SS":["a"]}}})
      )
    end

    it "marshals nested shapes" do
      input = Aws::DynamoDB::Types::CreateTableInput.new(
        table_name: "T",
        key_schema: [Aws::DynamoDB::Types::KeySchemaElement.new(attribute_name: "id", key_type: "HASH")],
        provisioned_throughput: Aws::DynamoDB::Types::ProvisionedThroughput.new(
          read_capacity_units: 5, write_capacity_units: 2
        )
      )
      input.to_wire.to_json.should eq(
        %({"TableName":"T","KeySchema":[{"AttributeName":"id","KeyType":"HASH"}],) +
        %("ProvisionedThroughput":{"ReadCapacityUnits":5,"WriteCapacityUnits":2}})
      )
    end

    describe "#merge" do
      it "overrides only the named fields" do
        input = Aws::DynamoDB::Types::GetItemInput.new(table_name: "T", consistent_read: true)
        merged = input.merge(table_name: "Other")
        merged.table_name.should eq("Other")
        merged.consistent_read.should be_true
      end

      it "leaves the receiver untouched" do
        input = Aws::DynamoDB::Types::GetItemInput.new(table_name: "T")
        input.merge(table_name: "Other")
        input.table_name.should eq("T")
      end

      it "can set a field that was nil" do
        input = Aws::DynamoDB::Types::GetItemInput.new(table_name: "T")
        input.merge(key: Aws::DynamoDB::Item{"id" => 1_i64}).key.should eq(Aws::DynamoDB::Item{"id" => 1_i64})
      end
    end

    describe "#to_named_tuple" do
      it "returns every field in declaration order" do
        tuple = Aws::DynamoDB::Types::DeleteTableInput.new(table_name: "T").to_named_tuple
        tuple.should eq({table_name: "T"})
      end
    end
  end

  describe "item operations" do
    it "round trips a PutItem output" do
      json = %({"Attributes":{"id":{"N":"1"}},"ConsumedCapacity":{"TableName":"T","CapacityUnits":1.0}})
      output = Aws::DynamoDB::Types::PutItemOutput.from_json(json)
      output.attributes.should eq(Aws::DynamoDB::Item{"id" => 1_i64})
      output.consumed_capacity.try(&.table_name).should eq("T")
      output.consumed_capacity.try(&.capacity_units).should eq(1.0)
    end

    it "parses a GetItem output without an item" do
      Aws::DynamoDB::Types::GetItemOutput.from_json("{}").item.should be_nil
    end

    it "builds an UpdateItem input with expression attributes" do
      input = Aws::DynamoDB::Types::UpdateItemInput.new(
        table_name: "T",
        key: Aws::DynamoDB::Item{"id" => 1_i64},
        update_expression: "SET #UE_A = :ue_a",
        expression_attribute_names: {"#UE_A" => "body"},
        expression_attribute_values: Aws::DynamoDB::Item{":ue_a" => "hello"}
      )
      input.to_wire.to_json.should eq(
        %({"TableName":"T","Key":{"id":{"N":"1"}},"UpdateExpression":"SET #UE_A = :ue_a",) +
        %("ExpressionAttributeNames":{"#UE_A":"body"},"ExpressionAttributeValues":{":ue_a":{"S":"hello"}}})
      )
    end

    it "builds a DeleteItem input" do
      input = Aws::DynamoDB::Types::DeleteItemInput.new(
        table_name: "T", key: Aws::DynamoDB::Item{"id" => 1_i64}
      )
      input.to_wire.to_json.should eq(%({"TableName":"T","Key":{"id":{"N":"1"}}}))
    end
  end

  describe "query and scan" do
    it "builds a Query input" do
      input = Aws::DynamoDB::Types::QueryInput.new(
        table_name: "T",
        index_name: "idx",
        key_condition_expression: "#H = :h",
        scan_index_forward: false,
        limit: 10
      )
      input.to_wire.to_json.should eq(
        %({"TableName":"T","IndexName":"idx","Limit":10,"ScanIndexForward":false,) +
        %("KeyConditionExpression":"#H = :h"})
      )
    end

    it "parses a Query output" do
      json = %({"Items":[{"id":{"N":"1"}},{"id":{"N":"2"}}],"Count":2,"ScannedCount":5,) +
             %("LastEvaluatedKey":{"id":{"N":"2"}}})
      output = Aws::DynamoDB::Types::QueryOutput.from_json(json)
      output.items.should eq([Aws::DynamoDB::Item{"id" => 1_i64}, Aws::DynamoDB::Item{"id" => 2_i64}])
      output.count.should eq(2)
      output.scanned_count.should eq(5)
      output.last_evaluated_key.should eq(Aws::DynamoDB::Item{"id" => 2_i64})
    end

    it "parses a Scan output with no items" do
      output = Aws::DynamoDB::Types::ScanOutput.from_json(%({"Items":[],"Count":0}))
      output.items.should eq([] of Aws::DynamoDB::Item)
      output.last_evaluated_key.should be_nil
    end
  end

  describe "the legacy condition parameters" do
    it "builds a Query input with key conditions" do
      input = Aws::DynamoDB::Types::QueryInput.new(
        table_name: "T",
        key_conditions: {
          "id" => Aws::DynamoDB::Types::Condition.new(
            attribute_value_list: [1_i64] of Aws::DynamoDB::Value, comparison_operator: "EQ"
          ),
        }
      )
      input.to_wire.to_json.should eq(
        %({"TableName":"T","KeyConditions":{"id":{"AttributeValueList":[{"N":"1"}],) +
        %("ComparisonOperator":"EQ"}}})
      )
    end

    it "parses a condition back from the wire" do
      condition = Aws::DynamoDB::Types::Condition.from_json(
        %({"AttributeValueList":[{"N":"1"},{"S":"x"}],"ComparisonOperator":"BETWEEN"})
      )
      condition.attribute_value_list.should eq([1_i64, "x"] of Aws::DynamoDB::Value)
      condition.comparison_operator.should eq("BETWEEN")
    end
  end

  describe "batch operations" do
    it "builds a BatchGetItem input" do
      input = Aws::DynamoDB::Types::BatchGetItemInput.new(
        request_items: {
          "T" => Aws::DynamoDB::Types::KeysAndAttributes.new(keys: [Aws::DynamoDB::Item{"id" => 1_i64}]),
        }
      )
      input.to_wire.to_json.should eq(%({"RequestItems":{"T":{"Keys":[{"id":{"N":"1"}}]}}}))
    end

    it "parses a BatchGetItem output" do
      json = %({"Responses":{"T":[{"id":{"N":"1"}}]},"UnprocessedKeys":{"T":{"Keys":[{"id":{"N":"2"}}]}}})
      output = Aws::DynamoDB::Types::BatchGetItemOutput.from_json(json)
      output.responses.should eq({"T" => [Aws::DynamoDB::Item{"id" => 1_i64}]})
      output.unprocessed_keys.try(&.["T"].keys).should eq([Aws::DynamoDB::Item{"id" => 2_i64}])
    end

    it "builds a BatchWriteItem input" do
      input = Aws::DynamoDB::Types::BatchWriteItemInput.new(
        request_items: {
          "T" => [
            Aws::DynamoDB::Types::WriteRequest.new(
              put_request: Aws::DynamoDB::Types::PutRequest.new(item: Aws::DynamoDB::Item{"id" => 1_i64})
            ),
            Aws::DynamoDB::Types::WriteRequest.new(
              delete_request: Aws::DynamoDB::Types::DeleteRequest.new(key: Aws::DynamoDB::Item{"id" => 2_i64})
            ),
          ],
        }
      )
      input.to_wire.to_json.should eq(
        %({"RequestItems":{"T":[{"PutRequest":{"Item":{"id":{"N":"1"}}}},) +
        %({"DeleteRequest":{"Key":{"id":{"N":"2"}}}}]}})
      )
    end

    it "parses a BatchWriteItem output with unprocessed items" do
      json = %({"UnprocessedItems":{"T":[{"PutRequest":{"Item":{"id":{"N":"1"}}}}]}})
      output = Aws::DynamoDB::Types::BatchWriteItemOutput.from_json(json)
      unprocessed = output.unprocessed_items.should_not be_nil
      unprocessed["T"].first.put_request.try(&.item).should eq(Aws::DynamoDB::Item{"id" => 1_i64})
    end
  end

  describe "round trips" do
    it "re-serializes a BatchGetItem output to the wire form it was parsed from" do
      json = %({"Responses":{"T":[{"id":{"N":"1"}},{"id":{"N":"2"}}]}})
      Aws::DynamoDB::Types::BatchGetItemOutput.from_json(json).to_wire.to_json.should eq(json)
    end

    it "re-serializes a Query output to the wire form it was parsed from" do
      json = %({"Items":[{"id":{"N":"1"}}],"Count":1})
      Aws::DynamoDB::Types::QueryOutput.from_json(json).to_wire.to_json.should eq(json)
    end
  end

  describe "transactions" do
    it "builds a TransactGetItems input" do
      input = Aws::DynamoDB::Types::TransactGetItemsInput.new(
        transact_items: [
          Aws::DynamoDB::Types::TransactGetItem.new(
            get: Aws::DynamoDB::Types::Get.new(table_name: "T", key: Aws::DynamoDB::Item{"id" => 1_i64})
          ),
        ]
      )
      input.to_wire.to_json.should eq(%({"TransactItems":[{"Get":{"TableName":"T","Key":{"id":{"N":"1"}}}}]}))
    end

    it "parses a TransactGetItems output with a missing item" do
      output = Aws::DynamoDB::Types::TransactGetItemsOutput.from_json(%({"Responses":[{"Item":{"id":{"N":"1"}}},{}]}))
      responses = output.responses.should_not be_nil
      responses[0].item.should eq(Aws::DynamoDB::Item{"id" => 1_i64})
      responses[1].item.should be_nil
    end

    it "builds a TransactWriteItems input with every action kind" do
      input = Aws::DynamoDB::Types::TransactWriteItemsInput.new(
        transact_items: [
          Aws::DynamoDB::Types::TransactWriteItem.new(
            put: Aws::DynamoDB::Types::Put.new(table_name: "T", item: Aws::DynamoDB::Item{"id" => 1_i64})
          ),
          Aws::DynamoDB::Types::TransactWriteItem.new(
            delete: Aws::DynamoDB::Types::Delete.new(table_name: "T", key: Aws::DynamoDB::Item{"id" => 2_i64})
          ),
          Aws::DynamoDB::Types::TransactWriteItem.new(
            update: Aws::DynamoDB::Types::Update.new(
              table_name: "T", key: Aws::DynamoDB::Item{"id" => 3_i64}, update_expression: "SET #A = :a"
            )
          ),
          Aws::DynamoDB::Types::TransactWriteItem.new(
            condition_check: Aws::DynamoDB::Types::ConditionCheck.new(
              table_name: "T", key: Aws::DynamoDB::Item{"id" => 4_i64}, condition_expression: "attribute_exists(#H)"
            )
          ),
        ]
      )
      input.to_wire.to_json.should eq(
        %({"TransactItems":[) +
        %({"Put":{"TableName":"T","Item":{"id":{"N":"1"}}}},) +
        %({"Delete":{"TableName":"T","Key":{"id":{"N":"2"}}}},) +
        %({"Update":{"TableName":"T","Key":{"id":{"N":"3"}},"UpdateExpression":"SET #A = :a"}},) +
        %({"ConditionCheck":{"TableName":"T","Key":{"id":{"N":"4"}},"ConditionExpression":"attribute_exists(#H)"}}) +
        %(]})
      )
    end
  end

  describe "table operations" do
    it "builds an UpdateTable input with index updates" do
      input = Aws::DynamoDB::Types::UpdateTableInput.new(
        table_name: "T",
        global_secondary_index_updates: [
          Aws::DynamoDB::Types::GlobalSecondaryIndexUpdate.new(
            update: Aws::DynamoDB::Types::UpdateGlobalSecondaryIndexAction.new(
              index_name: "idx",
              provisioned_throughput: Aws::DynamoDB::Types::ProvisionedThroughput.new(
                read_capacity_units: 1, write_capacity_units: 1
              )
            )
          ),
        ]
      )
      input.to_wire.to_json.should eq(
        %({"TableName":"T","GlobalSecondaryIndexUpdates":[{"Update":{"IndexName":"idx",) +
        %("ProvisionedThroughput":{"ReadCapacityUnits":1,"WriteCapacityUnits":1}}}]})
      )
    end

    it "parses a DescribeTable output" do
      json = <<-JSON
        {"Table":{"TableName":"T","TableStatus":"ACTIVE",
          "AttributeDefinitions":[{"AttributeName":"id","AttributeType":"S"}],
          "KeySchema":[{"AttributeName":"id","KeyType":"HASH"}],
          "ProvisionedThroughput":{"ReadCapacityUnits":5,"WriteCapacityUnits":2,"NumberOfDecreasesToday":0},
          "BillingModeSummary":{"BillingMode":"PROVISIONED"},
          "GlobalSecondaryIndexes":[{"IndexName":"idx","IndexStatus":"ACTIVE",
            "KeySchema":[{"AttributeName":"id","KeyType":"HASH"}],
            "Projection":{"ProjectionType":"ALL"}}]}}
        JSON
      table = Aws::DynamoDB::Types::DescribeTableOutput.from_json(json).table.should_not be_nil
      table.table_status.should eq("ACTIVE")
      table.attribute_definitions.try(&.first.attribute_type).should eq("S")
      table.provisioned_throughput.try(&.read_capacity_units).should eq(5)
      table.billing_mode_summary.try(&.billing_mode).should eq("PROVISIONED")
      table.global_secondary_indexes.try(&.first.projection.try(&.projection_type)).should eq("ALL")
    end

    it "parses a ListTables output" do
      output = Aws::DynamoDB::Types::ListTablesOutput.from_json(%({"TableNames":["a","b"]}))
      output.table_names.should eq(["a", "b"])
      output.last_evaluated_table_name.should be_nil
    end
  end

  describe "time to live" do
    it "builds an UpdateTimeToLive input" do
      input = Aws::DynamoDB::Types::UpdateTimeToLiveInput.new(
        table_name: "T",
        time_to_live_specification: Aws::DynamoDB::Types::TimeToLiveSpecification.new(
          enabled: true, attribute_name: "ttl"
        )
      )
      input.to_wire.to_json.should eq(
        %({"TableName":"T","TimeToLiveSpecification":{"Enabled":true,"AttributeName":"ttl"}})
      )
    end

    it "parses a DescribeTimeToLive output" do
      json = %({"TimeToLiveDescription":{"TimeToLiveStatus":"ENABLED","AttributeName":"ttl"}})
      description = Aws::DynamoDB::Types::DescribeTimeToLiveOutput.from_json(json)
        .time_to_live_description.should_not be_nil
      description.time_to_live_status.should eq("ENABLED")
      description.attribute_name.should eq("ttl")
    end
  end
end
