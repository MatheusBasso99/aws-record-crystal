require "../../spec_helper"

module ItemCollectionSpec
  class Model < Aws::Record::Base
    set_table_name "TestTable"
    integer_attr :id, hash_key: true
  end

  class ModelA < Aws::Record::Base
    set_table_name "TestTable"
    integer_attr :id, hash_key: true
    string_attr :class_name
    string_attr :attr_a
  end

  class ModelB < Aws::Record::Base
    set_table_name "TestTable"
    integer_attr :id, hash_key: true
    string_attr :class_name
    string_attr :attr_b
  end
end

private def scan_output(ids : Array(Int64), last_key : Int64? = nil) : Aws::DynamoDB::Types::ScanOutput
  Aws::DynamoDB::Types::ScanOutput.new(
    items: ids.map { |id| Aws::DynamoDB::Item{"id" => id} },
    count: ids.size,
    last_evaluated_key: last_key ? Aws::DynamoDB::Item{"id" => last_key} : nil
  )
end

private def truncated_resp : Aws::DynamoDB::Types::ScanOutput
  scan_output([1_i64, 2_i64, 3_i64], last_key: 3_i64)
end

private def non_truncated_resp : Aws::DynamoDB::Types::ScanOutput
  scan_output([4_i64, 5_i64])
end

private def collection(client : Aws::DynamoDB::Client, **opts) : Aws::Record::ItemCollection
  ItemCollectionSpec::Model.configure_client(client: client)
  ItemCollectionSpec::Model.scan(**opts)
end

private def ids(collection : Aws::Record::ItemCollection) : Array(Int64?)
  collection.map { |record| record.as(ItemCollectionSpec::Model).id }.to_a
end

describe Aws::Record::ItemCollection do
  describe "#page" do
    it "provides an array of items from a single client call" do
      client = stub_client
      client.stub_responses(:scan, truncated_resp)
      items = collection(client)

      page = items.page
      page.size.should eq(3)
      page.map { |record| record.as(ItemCollectionSpec::Model).id }.should eq([1_i64, 2_i64, 3_i64])
      items.last_evaluated_key.should eq(Aws::DynamoDB::Item{"id" => 3_i64})
    end
  end

  describe "#new_record" do
    it "marks a new record as being new" do
      record = ItemCollectionSpec::Model.new
      record.new_record?.should be_true
      record.destroyed?.should be_false
    end

    it "marks records fetched from a client call as not being new" do
      client = stub_client
      client.stub_responses(:scan, non_truncated_resp)
      collection(client).each do |record|
        record.new_record?.should be_false
        record.destroyed?.should be_false
      end
    end
  end

  describe "#new_record with ActiveModel::Model" do
    it "marks a new record as being new" do
      record = ItemCollectionSpec::Model.new
      record.new_record?.should be_true
      record.destroyed?.should be_false
    end

    it "marks records fetched from a client call as not being new" do
      client = stub_client
      client.stub_responses(:scan, non_truncated_resp)
      collection(client).each do |record|
        record.new_record?.should be_false
        record.destroyed?.should be_false
        record.persisted?.should be_true
      end
    end
  end

  describe "#last_evaluated_key" do
    it "points you to the client response pagination value if present" do
      client = stub_client
      client.stub_responses(:scan, truncated_resp)
      items = collection(client)
      items.first(2)
      items.last_evaluated_key.should eq(Aws::DynamoDB::Item{"id" => 3_i64})
    end

    it "provides a nil pagination value if no pages remain" do
      client = stub_client
      client.stub_responses(:scan, non_truncated_resp)
      items = collection(client)
      items.first(2)
      items.last_evaluated_key.should be_nil
    end

    it "correctly provides the most recent pagination key" do
      client = stub_client
      client.stub_responses(:scan, truncated_resp, non_truncated_resp)
      items = collection(client)
      items.first(4)
      items.last_evaluated_key.should be_nil
    end

    it "gathers evaluation keys from #page as well" do
      client = stub_client
      client.stub_responses(:scan, truncated_resp)
      items = collection(client)
      items.page
      items.last_evaluated_key.should eq(Aws::DynamoDB::Item{"id" => 3_i64})

      other_client = stub_client
      other_client.stub_responses(:scan, non_truncated_resp)
      other = collection(other_client)
      other.page
      other.last_evaluated_key.should be_nil
    end
  end

  describe "#each" do
    it "correctly iterates through a paginated response" do
      client = stub_client
      client.stub_responses(:scan, truncated_resp, non_truncated_resp)
      items = collection(client)

      ids(items).should eq([1_i64, 2_i64, 3_i64, 4_i64, 5_i64])
      api_requests(client).size.should eq(2)
    end

    it "makes the minimum number of required requests" do
      client = stub_client
      client.stub_responses(:scan, truncated_resp, non_truncated_resp)
      items = collection(client)

      items.first.as(ItemCollectionSpec::Model).id.should eq(1_i64)
      api_requests(client).size.should eq(1)
    end

    describe "model_filter is set" do
      filter = ->(item : Aws::DynamoDB::Item) do
        case item["class_name"]?
        when "A" then ItemCollectionSpec::ModelA.as(Aws::Record::Base.class)
        when "B" then ItemCollectionSpec::ModelB.as(Aws::Record::Base.class)
        end
      end

      mixed = Aws::DynamoDB::Types::ScanOutput.new(
        items: [
          Aws::DynamoDB::Item{"id" => 1_i64, "class_name" => "A", "attr_a" => "a"},
          Aws::DynamoDB::Item{"id" => 2_i64, "class_name" => "B", "attr_b" => "b"},
          Aws::DynamoDB::Item{"id" => 3_i64},
        ],
        count: 3
      )

      it "uses the model proc to determine the returned model classes" do
        client = stub_client
        client.stub_responses(:scan, mixed)
        ItemCollectionSpec::ModelA.configure_client(client: client)
        items = ItemCollectionSpec::ModelA.build_scan.multi_model_filter { |item| filter.call(item) }.complete!

        items.map(&.class).to_a.should eq([ItemCollectionSpec::ModelA, ItemCollectionSpec::ModelB])
      end

      it "maps class specific attributes" do
        client = stub_client
        client.stub_responses(:scan, mixed)
        ItemCollectionSpec::ModelA.configure_client(client: client)
        items = ItemCollectionSpec::ModelA.build_scan.multi_model_filter { |item| filter.call(item) }.complete!

        page = items.page
        page[0].as(ItemCollectionSpec::ModelA).attr_a.should eq("a")
        page[1].as(ItemCollectionSpec::ModelB).attr_b.should eq("b")
      end

      it "skips items when model_filter returns nil" do
        client = stub_client
        client.stub_responses(:scan, mixed)
        ItemCollectionSpec::ModelA.configure_client(client: client)
        items = ItemCollectionSpec::ModelA.build_scan.multi_model_filter { |item| filter.call(item) }.complete!

        items.page.size.should eq(2)
      end
    end
  end

  describe "#empty?" do
    it "is not empty" do
      client = stub_client
      client.stub_responses(:scan, scan_output([1_i64, 2_i64, 3_i64]))
      collection(client).empty?.should be_false
    end

    it "is empty" do
      client = stub_client
      client.stub_responses(:scan, scan_output([] of Int64))
      collection(client).empty?.should be_true
    end

    it "handles initial pages being empty" do
      client = stub_client
      client.stub_responses(
        :scan,
        scan_output([] of Int64, last_key: 3_i64),
        scan_output([1_i64, 2_i64, 3_i64])
      )
      collection(client, limit: 3).empty?.should be_false
    end

    it "handles final pages being empty" do
      client = stub_client
      client.stub_responses(:scan, truncated_resp, scan_output([] of Int64))
      collection(client).empty?.should be_false
    end
  end
end

# Parity: 18/18 examples from spec/aws-record/record/item_collection_spec.rb (aws-record 2.15.1)
