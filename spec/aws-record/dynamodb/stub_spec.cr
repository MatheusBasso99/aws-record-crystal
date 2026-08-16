require "../../spec_helper"

private def describe_table_output(status : String = "ACTIVE") : Aws::DynamoDB::Types::DescribeTableOutput
  Aws::DynamoDB::Types::DescribeTableOutput.new(
    table: Aws::DynamoDB::Types::TableDescription.new(table_status: status)
  )
end

describe Aws::DynamoDB::Stub do
  describe ".from" do
    it "turns a typed output shape into its wire JSON" do
      Aws::DynamoDB::Stub.from(describe_table_output).body
        .should eq(%({"Table":{"TableStatus":"ACTIVE"}}))
    end

    it "turns a String into the DynamoDB error with that code" do
      error = Aws::DynamoDB::Stub.from("ResourceNotFoundException").error
      error.should be_a(Aws::DynamoDB::Errors::ResourceNotFoundException)
    end

    it "keeps an exception as it is" do
      raised = Aws::DynamoDB::Errors::ValidationException.new("bad")
      Aws::DynamoDB::Stub.from(raised).error.should be(raised)
    end

    it "keeps a stub as it is" do
      stub = Aws::DynamoDB::Stub.json("{}")
      Aws::DynamoDB::Stub.from(stub).should eq(stub)
    end
  end

  describe "#take" do
    it "returns the body of a response stub" do
      Aws::DynamoDB::Stub.json(%({"a":1})).take.should eq(%({"a":1}))
    end

    it "raises the error of an error stub" do
      expect_raises(Aws::DynamoDB::Errors::ValidationException, "bad") do
        Aws::DynamoDB::Stub.from(Aws::DynamoDB::Errors::ValidationException.new("bad")).take
      end
    end
  end
end

describe "Aws::DynamoDB::Client stubbing" do
  it "answers with an empty response when nothing is stubbed" do
    stub_client.describe_table(table_name: "T").table.should be_nil
  end

  it "answers with a stubbed typed output" do
    client = stub_client
    client.stub_responses(:describe_table, describe_table_output)
    client.describe_table(table_name: "T").table.try(&.table_status).should eq("ACTIVE")
  end

  it "answers with raw wire JSON" do
    client = stub_client
    client.stub_responses(:scan, Aws::DynamoDB::Stub.json(%({"Items":[{"id":{"N":"1"}}],"Count":1})))
    output = client.scan(table_name: "T")
    output.count.should eq(1)
    output.items.should eq([Aws::DynamoDB::Item{"id" => 1_i64}])
  end

  it "raises the error named by a String stub" do
    client = stub_client
    client.stub_responses(:describe_table, "ResourceNotFoundException")
    expect_raises(Aws::DynamoDB::Errors::ResourceNotFoundException) { client.describe_table(table_name: "T") }
  end

  it "raises a stubbed exception, keeping the data it carries" do
    client = stub_client
    raised = Aws::DynamoDB::Errors::ConditionalCheckFailedException.new("nope")
    raised.item = Aws::DynamoDB::Item{"id" => 1_i64}
    client.stub_responses(:put_item, raised)
    error = expect_raises(Aws::DynamoDB::Errors::ConditionalCheckFailedException) do
      client.put_item(table_name: "T", item: Aws::DynamoDB::Item.new)
    end
    error.item.should eq(Aws::DynamoDB::Item{"id" => 1_i64})
  end

  it "walks a sequence of stubs, mixing errors and responses" do
    client = stub_client
    client.stub_responses(:describe_table, "ResourceNotFoundException", describe_table_output("CREATING"))

    expect_raises(Aws::DynamoDB::Errors::ResourceNotFoundException) { client.describe_table(table_name: "T") }
    client.describe_table(table_name: "T").table.try(&.table_status).should eq("CREATING")
  end

  it "repeats the last stub once the sequence runs out" do
    client = stub_client
    client.stub_responses(:describe_table, describe_table_output("CREATING"), describe_table_output("ACTIVE"))

    client.describe_table(table_name: "T").table.try(&.table_status).should eq("CREATING")
    3.times { client.describe_table(table_name: "T").table.try(&.table_status).should eq("ACTIVE") }
  end

  it "keeps a separate queue per operation" do
    client = stub_client
    client.stub_responses(:describe_table, describe_table_output)
    client.stub_responses(:scan, Aws::DynamoDB::Stub.json(%({"Count":7})))

    client.describe_table(table_name: "T").table.try(&.table_status).should eq("ACTIVE")
    client.scan(table_name: "T").count.should eq(7)
  end

  describe "#api_requests" do
    it "records every call, in order, with its typed input" do
      client = stub_client
      client.put_item(table_name: "T", item: Aws::DynamoDB::Item{"id" => 1_i64})
      client.get_item(table_name: "T", key: Aws::DynamoDB::Item{"id" => 1_i64})

      requests = api_requests(client)
      requests.size.should eq(2)
      requests[0].operation.should eq(Aws::DynamoDB::Operation::PutItem)
      requests[0].input.as(Aws::DynamoDB::Types::PutItemInput).table_name.should eq("T")
      requests[1].operation.should eq(Aws::DynamoDB::Operation::GetItem)
      requests[1].input.as(Aws::DynamoDB::Types::GetItemInput).key.should eq(Aws::DynamoDB::Item{"id" => 1_i64})
    end

    it "records the wire form of each call" do
      client = stub_client
      client.put_item(table_name: "T", item: Aws::DynamoDB::Item{"id" => 1_i64})
      api_requests(client)[0].params["Item"]["id"]["N"].should eq("1")
    end

    it "records a call that raised" do
      client = stub_client
      client.stub_responses(:describe_table, "ResourceNotFoundException")
      expect_raises(Aws::DynamoDB::Errors::ResourceNotFoundException) { client.describe_table(table_name: "T") }
      api_requests(client).size.should eq(1)
    end

    it "can be cleared" do
      client = stub_client
      client.describe_table(table_name: "T")
      client.clear_api_requests
      api_requests(client).should be_empty
    end
  end

  describe "#before_request" do
    it "runs its callbacks with every call" do
      client = stub_client
      seen = [] of String
      client.before_request { |call| seen << call.operation.to_s }
      client.describe_table(table_name: "T")
      client.scan(table_name: "T")
      seen.should eq(["DescribeTable", "Scan"])
    end

    it "runs every registered callback" do
      client = stub_client
      count = 0
      client.before_request { count += 1 }
      client.before_request { count += 1 }
      client.describe_table(table_name: "T")
      count.should eq(2)
    end
  end

  it "cannot be asked to send a request" do
    client = stub_client
    client.config.stub_responses?.should be_true
  end
end
