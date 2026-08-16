require "../../spec_helper"

private def table(status : String) : Aws::DynamoDB::Types::DescribeTableOutput
  Aws::DynamoDB::Types::DescribeTableOutput.new(
    table: Aws::DynamoDB::Types::TableDescription.new(table_status: status, table_name: "T")
  )
end

describe "Aws::DynamoDB::Client waiters" do
  describe "#wait_until_table_exists" do
    it "returns as soon as the table is ACTIVE" do
      client = stub_client
      client.stub_responses(:describe_table, table("ACTIVE"))

      description = client.wait_until_table_exists("T")
      description.table_status.should eq("ACTIVE")
      api_requests(client).size.should eq(1)
    end

    it "polls while the table is still being created" do
      client = stub_client
      client.stub_responses(:describe_table, table("CREATING"), table("CREATING"), table("ACTIVE"))

      client.wait_until_table_exists("T").table_status.should eq("ACTIVE")
      api_requests(client).size.should eq(3)
    end

    it "polls while the table does not exist yet" do
      client = stub_client
      client.stub_responses(:describe_table, "ResourceNotFoundException", table("ACTIVE"))

      client.wait_until_table_exists("T").table_status.should eq("ACTIVE")
      api_requests(client).size.should eq(2)
    end

    it "gives up after max_attempts" do
      client = stub_client
      client.stub_responses(:describe_table, table("CREATING"))

      expect_raises(Aws::DynamoDB::Errors::WaiterFailed, "was not ACTIVE after 3 attempts") do
        client.wait_until_table_exists("T", max_attempts: 3)
      end
      api_requests(client).size.should eq(3)
    end

    it "does not swallow errors other than ResourceNotFoundException" do
      client = stub_client
      client.stub_responses(:describe_table, "ValidationException")
      expect_raises(Aws::DynamoDB::Errors::ValidationException) { client.wait_until_table_exists("T") }
    end
  end

  describe "#wait_until_table_not_exists" do
    it "returns as soon as the table is gone" do
      client = stub_client
      client.stub_responses(:describe_table, "ResourceNotFoundException")

      client.wait_until_table_not_exists("T")
      api_requests(client).size.should eq(1)
    end

    it "polls while the table is still being deleted" do
      client = stub_client
      client.stub_responses(:describe_table, table("DELETING"), "ResourceNotFoundException")

      client.wait_until_table_not_exists("T")
      api_requests(client).size.should eq(2)
    end

    it "gives up after max_attempts" do
      client = stub_client
      client.stub_responses(:describe_table, table("ACTIVE"))

      expect_raises(Aws::DynamoDB::Errors::WaiterFailed, "still existed after 2 attempts") do
        client.wait_until_table_not_exists("T", max_attempts: 2)
      end
    end
  end
end
