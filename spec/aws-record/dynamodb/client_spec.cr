require "../../spec_helper"

describe Aws::DynamoDB::Client do
  describe "the request it sends" do
    it "posts JSON 1.0 to the configured endpoint" do
      captured = stub_endpoint
      live_client.describe_table(table_name: "T")

      captured.size.should eq(1)
      request = captured.first
      request.method.should eq("POST")
      request.headers["Content-Type"].should eq("application/x-amz-json-1.0")
      request.target.should eq("DynamoDB_20120810.DescribeTable")
      request.body.should eq(%({"TableName":"T"}))
    end

    it "names the shard in the User-Agent" do
      captured = stub_endpoint
      live_client.describe_table(table_name: "T")
      captured.first.headers["User-Agent"].should start_with("aws-record-crystal/")
      captured.first.headers["User-Agent"].should contain("crystal/")
    end

    it "appends the user agent frameworks of its config" do
      captured = stub_endpoint
      client = live_client(user_agent_frameworks: ["aws-record"])
      client.describe_table(table_name: "T")
      captured.first.headers["User-Agent"].should end_with(" aws-record")
    end

    it "signs the request with SigV4" do
      captured = stub_endpoint
      live_client.describe_table(table_name: "T")
      authorization = captured.first.headers["Authorization"]
      authorization.should start_with("AWS4-HMAC-SHA256 ")
      authorization.should contain("Credential=akid/")
      authorization.should contain("/us-east-1/dynamodb/aws4_request")
      authorization.should contain("Signature=")
      captured.first.headers["X-Amz-Date"]?.should_not be_nil
      captured.first.headers["X-Amz-Content-Sha256"]?.should_not be_nil
    end

    it "sends the session token of temporary credentials" do
      captured = stub_endpoint
      credentials = Aws::DynamoDB::Credentials.new("akid", "secret", "session-token")
      live_client(credentials: credentials).describe_table(table_name: "T")
      captured.first.headers["X-Amz-Security-Token"].should eq("session-token")
    end

    it "closes its pooled connections" do
      stub_endpoint
      client = live_client
      client.describe_table(table_name: "T")
      client.close
      client.describe_table(table_name: "T")
    end

    it "targets a custom endpoint" do
      captured = stub_endpoint(endpoint: "http://localhost:8000")
      live_client(endpoint: "http://localhost:8000").describe_table(table_name: "T")
      captured.size.should eq(1)
      captured.first.headers["Host"].should eq("localhost:8000")
    end
  end

  describe "every operation" do
    it "sends the wire form of put_item and parses its response" do
      captured = stub_endpoint([{200, %({"Attributes":{"id":{"N":"1"}}})}])
      output = live_client.put_item(table_name: "T", item: Aws::DynamoDB::Item{"id" => 1_i64})

      captured.first.target.should eq("DynamoDB_20120810.PutItem")
      captured.first.json["Item"]["id"]["N"].should eq("1")
      output.attributes.should eq(Aws::DynamoDB::Item{"id" => 1_i64})
    end

    it "sends the wire form of get_item and parses its response" do
      captured = stub_endpoint([{200, %({"Item":{"id":{"N":"1"},"body":{"S":"hello"}}})}])
      output = live_client.get_item(table_name: "T", key: Aws::DynamoDB::Item{"id" => 1_i64})

      captured.first.target.should eq("DynamoDB_20120810.GetItem")
      captured.first.json["Key"]["id"]["N"].should eq("1")
      output.item.should eq(Aws::DynamoDB::Item{"id" => 1_i64, "body" => "hello"})
    end

    it "sends the wire form of update_item and parses its response" do
      captured = stub_endpoint([{200, %({"Attributes":{"body":{"S":"new"}}})}])
      output = live_client.update_item(
        table_name: "T",
        key: Aws::DynamoDB::Item{"id" => 1_i64},
        update_expression: "SET #UE_A = :ue_a",
        expression_attribute_names: {"#UE_A" => "body"},
        expression_attribute_values: Aws::DynamoDB::Item{":ue_a" => "new"},
        return_values: "UPDATED_NEW"
      )

      captured.first.target.should eq("DynamoDB_20120810.UpdateItem")
      captured.first.json["UpdateExpression"].should eq("SET #UE_A = :ue_a")
      captured.first.json["ExpressionAttributeValues"][":ue_a"]["S"].should eq("new")
      captured.first.json["ReturnValues"].should eq("UPDATED_NEW")
      output.attributes.should eq(Aws::DynamoDB::Item{"body" => "new"})
    end

    it "sends the wire form of delete_item" do
      captured = stub_endpoint
      live_client.delete_item(table_name: "T", key: Aws::DynamoDB::Item{"id" => 1_i64})
      captured.first.target.should eq("DynamoDB_20120810.DeleteItem")
      captured.first.json["Key"]["id"]["N"].should eq("1")
    end

    it "sends the wire form of query and parses its response" do
      captured = stub_endpoint([{200, %({"Items":[{"id":{"N":"1"}}],"Count":1,"ScannedCount":1})}])
      output = live_client.query(
        table_name: "T",
        key_condition_expression: "#H = :h",
        expression_attribute_names: {"#H" => "id"},
        expression_attribute_values: Aws::DynamoDB::Item{":h" => 1_i64}
      )

      captured.first.target.should eq("DynamoDB_20120810.Query")
      captured.first.json["KeyConditionExpression"].should eq("#H = :h")
      output.count.should eq(1)
      output.items.should eq([Aws::DynamoDB::Item{"id" => 1_i64}])
    end

    it "sends the wire form of scan and parses its response" do
      captured = stub_endpoint([{200, %({"Items":[],"Count":0})}])
      output = live_client.scan(table_name: "T", total_segments: 2, segment: 0)

      captured.first.target.should eq("DynamoDB_20120810.Scan")
      captured.first.json["TotalSegments"].should eq(2)
      output.items.should eq([] of Aws::DynamoDB::Item)
    end

    it "sends the wire form of batch_get_item and parses its response" do
      captured = stub_endpoint([{200, %({"Responses":{"T":[{"id":{"N":"1"}}]},"UnprocessedKeys":{}})}])
      output = live_client.batch_get_item(
        request_items: {
          "T" => Aws::DynamoDB::Types::KeysAndAttributes.new(keys: [Aws::DynamoDB::Item{"id" => 1_i64}]),
        }
      )

      captured.first.target.should eq("DynamoDB_20120810.BatchGetItem")
      captured.first.json["RequestItems"]["T"]["Keys"][0]["id"]["N"].should eq("1")
      output.responses.should eq({"T" => [Aws::DynamoDB::Item{"id" => 1_i64}]})
      output.unprocessed_keys.should eq({} of String => Aws::DynamoDB::Types::KeysAndAttributes)
    end

    it "sends the wire form of batch_write_item and parses its response" do
      captured = stub_endpoint([{200, %({"UnprocessedItems":{}})}])
      output = live_client.batch_write_item(
        request_items: {
          "T" => [Aws::DynamoDB::Types::WriteRequest.new(
            put_request: Aws::DynamoDB::Types::PutRequest.new(item: Aws::DynamoDB::Item{"id" => 1_i64})
          )],
        }
      )

      captured.first.target.should eq("DynamoDB_20120810.BatchWriteItem")
      captured.first.json["RequestItems"]["T"][0]["PutRequest"]["Item"]["id"]["N"].should eq("1")
      output.unprocessed_items.should eq({} of String => Array(Aws::DynamoDB::Types::WriteRequest))
    end

    it "sends the wire form of transact_get_items and parses its response" do
      captured = stub_endpoint([{200, %({"Responses":[{"Item":{"id":{"N":"1"}}},{}]})}])
      output = live_client.transact_get_items(
        transact_items: [
          Aws::DynamoDB::Types::TransactGetItem.new(
            get: Aws::DynamoDB::Types::Get.new(table_name: "T", key: Aws::DynamoDB::Item{"id" => 1_i64})
          ),
        ]
      )

      captured.first.target.should eq("DynamoDB_20120810.TransactGetItems")
      captured.first.json["TransactItems"][0]["Get"]["TableName"].should eq("T")
      output.responses.try(&.size).should eq(2)
      output.responses.try(&.[1].item).should be_nil
    end

    it "sends the wire form of transact_write_items" do
      captured = stub_endpoint
      live_client.transact_write_items(
        transact_items: [
          Aws::DynamoDB::Types::TransactWriteItem.new(
            put: Aws::DynamoDB::Types::Put.new(table_name: "T", item: Aws::DynamoDB::Item{"id" => 1_i64})
          ),
        ],
        client_request_token: "token"
      )

      captured.first.target.should eq("DynamoDB_20120810.TransactWriteItems")
      captured.first.json["ClientRequestToken"].should eq("token")
    end

    it "sends the wire form of create_table and parses its response" do
      captured = stub_endpoint([{200, %({"TableDescription":{"TableName":"T","TableStatus":"CREATING"}})}])
      output = live_client.create_table(
        table_name: "T",
        attribute_definitions: [
          Aws::DynamoDB::Types::AttributeDefinition.new(attribute_name: "id", attribute_type: "N"),
        ],
        key_schema: [Aws::DynamoDB::Types::KeySchemaElement.new(attribute_name: "id", key_type: "HASH")],
        provisioned_throughput: Aws::DynamoDB::Types::ProvisionedThroughput.new(
          read_capacity_units: 5, write_capacity_units: 2
        )
      )

      captured.first.target.should eq("DynamoDB_20120810.CreateTable")
      captured.first.json["AttributeDefinitions"][0]["AttributeType"].should eq("N")
      output.table_description.try(&.table_status).should eq("CREATING")
    end

    it "sends the wire form of update_table" do
      captured = stub_endpoint([{200, %({"TableDescription":{"TableStatus":"UPDATING"}})}])
      live_client.update_table(
        table_name: "T",
        provisioned_throughput: Aws::DynamoDB::Types::ProvisionedThroughput.new(
          read_capacity_units: 10, write_capacity_units: 5
        )
      )
      captured.first.target.should eq("DynamoDB_20120810.UpdateTable")
      captured.first.json["ProvisionedThroughput"]["ReadCapacityUnits"].should eq(10)
    end

    it "sends the wire form of delete_table" do
      captured = stub_endpoint([{200, %({"TableDescription":{"TableStatus":"DELETING"}})}])
      output = live_client.delete_table(table_name: "T")
      captured.first.target.should eq("DynamoDB_20120810.DeleteTable")
      output.table_description.try(&.table_status).should eq("DELETING")
    end

    it "sends the wire form of describe_table and parses its response" do
      body = %({"Table":{"TableName":"T","TableStatus":"ACTIVE","ItemCount":3}})
      captured = stub_endpoint([{200, body}])
      output = live_client.describe_table(table_name: "T")
      captured.first.target.should eq("DynamoDB_20120810.DescribeTable")
      output.table.try(&.item_count).should eq(3)
    end

    it "sends the wire form of list_tables and parses its response" do
      captured = stub_endpoint([{200, %({"TableNames":["a","b"]})}])
      output = live_client.list_tables(limit: 2)
      captured.first.target.should eq("DynamoDB_20120810.ListTables")
      captured.first.json["Limit"].should eq(2)
      output.table_names.should eq(["a", "b"])
    end

    it "sends the wire form of describe_time_to_live and parses its response" do
      body = %({"TimeToLiveDescription":{"TimeToLiveStatus":"ENABLED","AttributeName":"ttl"}})
      captured = stub_endpoint([{200, body}])
      output = live_client.describe_time_to_live(table_name: "T")
      captured.first.target.should eq("DynamoDB_20120810.DescribeTimeToLive")
      output.time_to_live_description.try(&.attribute_name).should eq("ttl")
    end

    it "sends the wire form of update_time_to_live" do
      body = %({"TimeToLiveSpecification":{"Enabled":true,"AttributeName":"ttl"}})
      captured = stub_endpoint([{200, body}])
      output = live_client.update_time_to_live(
        table_name: "T",
        time_to_live_specification: Aws::DynamoDB::Types::TimeToLiveSpecification.new(
          enabled: true, attribute_name: "ttl"
        )
      )
      captured.first.target.should eq("DynamoDB_20120810.UpdateTimeToLive")
      captured.first.json["TimeToLiveSpecification"]["Enabled"].should be_true
      output.time_to_live_specification.try(&.enabled).should be_true
    end
  end

  describe "error handling" do
    it "raises the error class matching the __type of the response" do
      stub_endpoint([{400, error_body("ResourceNotFoundException", "Requested resource not found")}])
      error = expect_raises(Aws::DynamoDB::Errors::ResourceNotFoundException, "Requested resource not found") do
        live_client.describe_table(table_name: "T")
      end
      error.http_status.should eq(400)
      error.request_id.should eq("req-1")
    end

    it "raises a plain ServiceError for an unknown code" do
      stub_endpoint([{400, error_body("BrandNewException")}])
      error = expect_raises(Aws::DynamoDB::Errors::ServiceError) { live_client.describe_table(table_name: "T") }
      error.code.should eq("BrandNewException")
    end

    it "raises a ServiceError when the body carries no __type" do
      stub_endpoint([{500, "not json at all"}])
      error = expect_raises(Aws::DynamoDB::Errors::ServiceError) { live_client.describe_table(table_name: "T") }
      error.code.should eq("ServiceError")
      error.http_status.should eq(500)
    end

    it "attaches the item of a failed conditional check" do
      body = %({"__type":"com.amazonaws.dynamodb.v20120810#ConditionalCheckFailedException",) +
             %("message":"The conditional request failed","Item":{"id":{"N":"1"}}})
      stub_endpoint([{400, body}])
      error = expect_raises(Aws::DynamoDB::Errors::ConditionalCheckFailedException) do
        live_client.put_item(table_name: "T", item: Aws::DynamoDB::Item{"id" => 1_i64})
      end
      error.item.should eq(Aws::DynamoDB::Item{"id" => 1_i64})
    end
  end

  describe "retries" do
    it "retries a throttled request and returns the eventual success" do
      responses = [
        {400, error_body("ThrottlingException")},
        {200, %({"Table":{"TableStatus":"ACTIVE"}})},
      ] of Tuple(Int32, String)
      captured = stub_endpoint(responses)

      live_client.describe_table(table_name: "T").table.try(&.table_status).should eq("ACTIVE")
      captured.size.should eq(2)
    end

    it "retries a 500 and gives up after max_attempts" do
      captured = stub_endpoint([{500, error_body("InternalServerError")}])
      expect_raises(Aws::DynamoDB::Errors::InternalServerError) do
        live_client(max_attempts: 3).describe_table(table_name: "T")
      end
      captured.size.should eq(3)
    end

    it "never retries a validation error" do
      captured = stub_endpoint([{400, error_body("ValidationException")}])
      expect_raises(Aws::DynamoDB::Errors::ValidationException) { live_client.describe_table(table_name: "T") }
      captured.size.should eq(1)
    end

    it "never retries a conditional check failure" do
      captured = stub_endpoint([{400, error_body("ConditionalCheckFailedException")}])
      expect_raises(Aws::DynamoDB::Errors::ConditionalCheckFailedException) do
        live_client.put_item(table_name: "T", item: Aws::DynamoDB::Item.new)
      end
      captured.size.should eq(1)
    end

    it "sends a single request when max_attempts is one" do
      captured = stub_endpoint([{500, error_body("InternalServerError")}])
      expect_raises(Aws::DynamoDB::Errors::InternalServerError) do
        live_client(max_attempts: 1).describe_table(table_name: "T")
      end
      captured.size.should eq(1)
    end
  end
end
