require "../../spec_helper"

private def page(items : Array(Int64), last_key : Int64? = nil) : String
  json = String.build do |io|
    io << %({"Items":[)
    items.each_with_index do |value, index|
      io << ',' if index > 0
      io << %({"id":{"N":") << value << %("}})
    end
    io << %(],"Count":) << items.size
    io << %(,"LastEvaluatedKey":{"id":{"N":") << last_key << %("}}) if last_key
    io << '}'
  end
  json
end

describe Aws::DynamoDB::Pages do
  describe "#first_page" do
    it "fetches the first page once" do
      client = stub_client
      client.stub_responses(:scan, Aws::DynamoDB::Stub.json(page([1_i64])))
      pages = client.scan_pages(table_name: "T")

      pages.first_page.count.should eq(1)
      pages.first_page.count.should eq(1)
      api_requests(client).size.should eq(1)
    end
  end

  describe "#each_page" do
    it "yields a single page when the service returns no key" do
      client = stub_client
      client.stub_responses(:scan, Aws::DynamoDB::Stub.json(page([1_i64, 2_i64])))

      collected = [] of Int32
      client.scan_pages(table_name: "T").each_page { |result| collected << (result.count || 0) }
      collected.should eq([2])
      api_requests(client).size.should eq(1)
    end

    it "follows the last evaluated key until the service stops sending one" do
      client = stub_client
      client.stub_responses(
        :scan,
        Aws::DynamoDB::Stub.json(page([1_i64, 2_i64], last_key: 2_i64)),
        Aws::DynamoDB::Stub.json(page([3_i64], last_key: 3_i64)),
        Aws::DynamoDB::Stub.json(page([] of Int64))
      )

      ids = [] of Aws::DynamoDB::Value
      client.scan_pages(table_name: "T").each_item { |item| ids << item["id"] }
      ids.should eq([1_i64, 2_i64, 3_i64] of Aws::DynamoDB::Value)
      api_requests(client).size.should eq(3)
    end

    it "sends the previous page's key as the exclusive start key" do
      client = stub_client
      client.stub_responses(
        :scan,
        Aws::DynamoDB::Stub.json(page([1_i64], last_key: 1_i64)),
        Aws::DynamoDB::Stub.json(page([2_i64]))
      )

      client.scan_pages(table_name: "T").each_page { }
      second = api_requests(client)[1].input.as(Aws::DynamoDB::Types::ScanInput)
      second.exclusive_start_key.should eq(Aws::DynamoDB::Item{"id" => 1_i64})
      second.table_name.should eq("T")
    end

    it "stops on an empty last evaluated key" do
      client = stub_client
      client.stub_responses(:scan, Aws::DynamoDB::Stub.json(%({"Items":[],"Count":0,"LastEvaluatedKey":{}})))
      pages = 0
      client.scan_pages(table_name: "T").each_page { pages += 1 }
      pages.should eq(1)
    end

    it "paginates queries as well" do
      client = stub_client
      client.stub_responses(
        :query,
        Aws::DynamoDB::Stub.json(page([1_i64], last_key: 1_i64)),
        Aws::DynamoDB::Stub.json(page([2_i64]))
      )

      ids = [] of Aws::DynamoDB::Value
      client.query_pages(table_name: "T", key_condition_expression: "#H = :h")
        .each_item { |item| ids << item["id"] }
      ids.should eq([1_i64, 2_i64] of Aws::DynamoDB::Value)
    end
  end
end
