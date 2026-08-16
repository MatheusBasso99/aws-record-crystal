require "../../spec_helper"

module AttributesSpec
  class InitializeModel < Aws::Record::Base
    string_attr :id, hash_key: true
    string_attr :body
  end

  class HashKeyModel < Aws::Record::Base
    string_attr :mykey, hash_key: true
    string_attr :other
  end

  class HashAndRangeKeyModel < Aws::Record::Base
    string_attr :mykey, hash_key: true
    string_attr :ranged, range_key: true
    string_attr :other
  end

  class TextModel < Aws::Record::Base
    string_attr :text
  end

  class NumModel < Aws::Record::Base
    integer_attr :num
  end

  class RawValuesModel < Aws::Record::Base
    string_attr :a
    string_attr :b
  end

  class StorageNameModel < Aws::Record::Base
    string_attr :a, database_attribute_name: "column_a"
    string_attr :b
  end

  class ReservedStorageNameModel < Aws::Record::Base
    string_attr :clever, database_attribute_name: "to_h"
  end

  class CounterWithDefaultModel < Aws::Record::Base
    string_attr :id, hash_key: true
    atomic_counter :counter, default_value: 5
  end

  class CounterModel < Aws::Record::Base
    string_attr :id, hash_key: true
    atomic_counter :counter
  end

  class IncrementModel < Aws::Record::Base
    set_table_name "TestTable"
    integer_attr :id, hash_key: true
    atomic_counter :counter
  end

  class ParentModel < Aws::Record::Base
    integer_attr :id, hash_key: true
    date_attr :date, range_key: true
    list_attr :list
    string_attr :test, default_value: -> { "test" }
  end

  class ChildModel < ParentModel
    string_attr :body
  end

  class ChildModel2 < ParentModel
    string_attr :body2
  end

  class KeyOverrideParent < Aws::Record::Base
    integer_attr :id, hash_key: true
    date_attr :date, range_key: true
    list_attr :list
  end

  class KeyOverrideChild < KeyOverrideParent
    string_attr :body
    integer_attr :rk, range_key: true
  end
end

describe "Attributes" do
  describe "#initialize" do
    it "should allow attribute assignment at item creation time" do
      item = AttributesSpec::InitializeModel.new(id: "MyId")
      item.id.should eq("MyId")
      item.body.should be_nil
    end

    it "should allow assignment of multiple attributes at item creation" do
      item = AttributesSpec::InitializeModel.new(id: "MyId", body: "Hello!")
      item.id.should eq("MyId")
      item.body.should eq("Hello!")
    end
  end

  describe "Keys" do
    it "should be able to assign a hash key" do
      # Key names are `String` here; Crystal cannot create symbols at runtime.
      AttributesSpec::HashKeyModel.hash_key.should eq("mykey")
    end

    it "should be able to assign a hash and range key" do
      AttributesSpec::HashAndRangeKeyModel.hash_key.should eq("mykey")
      AttributesSpec::HashAndRangeKeyModel.range_key.should eq("ranged")
    end

    it "should reject assigning the same attribute as hash and range key" do
      expect_compile_error(
        "same_hash_and_range_key.cr", "Cannot have the same attribute be a hash and range key."
      )
    end
  end

  describe "Attributes" do
    it "should create dynamic methods around attributes" do
      item = AttributesSpec::TextModel.new
      item.text = "Hello world!"
      item.text.should eq("Hello world!")
    end

    it "should reject non-symbolized attribute names" do
      expect_compile_error("non_symbol_name.cr", "Must use symbolized :name attribute")
    end

    it "rejects collisions of db storage names with existing attr names" do
      expect_compile_error(
        "storage_name_collides_with_attr_name.cr", "already exists as an attribute name"
      )
    end

    it "rejects collisions of attr names with existing db storage names" do
      expect_compile_error(
        "attr_name_collides_with_storage_name.cr", "already exists as an attribute name"
      )
    end

    it "should not allow duplicate assignment of the same attr name" do
      expect_compile_error("duplicate_attr_name.cr", "Cannot overwrite existing attribute duplication")
    end

    it "should typecast an integer attribute" do
      item = AttributesSpec::NumModel.new
      item.num = "5"
      item.num.should eq(5)
    end

    it "should display a hash representation of attribute raw values" do
      item = AttributesSpec::RawValuesModel.new
      item.a = "5"
      item.b = 5
      item.to_h.should eq({"a" => "5", "b" => 5_i64})
    end

    it "should allow specification of a separate storage attribute name" do
      AttributesSpec::StorageNameModel.attributes.storage_name_for(:a).should eq("column_a")
      AttributesSpec::StorageNameModel.attributes.storage_name_for(:b).should eq("b")
    end

    it "should reject storage name collisions" do
      expect_compile_error("storage_name_collision.cr", "Custom storage name column_a already in use")
    end

    it "should enforce uniqueness of storage names" do
      expect_compile_error("duplicate_storage_name.cr", "Custom storage name unique already in use")
    end

    it "should not allow collisions with reserved names" do
      expect_compile_error("reserved_name.cr", "that would collide with an existing instance method")
    end

    it "should allow reserved names to be used as custom storage names" do
      item = AttributesSpec::ReservedStorageNameModel.new
      item.clever = "No problem."
      item.to_h.should eq({"clever" => "No problem."})
      AttributesSpec::ReservedStorageNameModel.attributes.storage_name_for(:clever).should eq("to_h")
    end
  end

  describe "#atomic_counter" do
    it "should override the existing default value" do
      AttributesSpec::CounterWithDefaultModel.new(id: "MyId").counter.should eq(5)
    end

    it "should be the existing default value" do
      AttributesSpec::CounterModel.new(id: "MyId").counter.should eq(0)
    end

    it "should be able to reassign default value after creation" do
      item = AttributesSpec::CounterWithDefaultModel.new(id: "MyId")
      item.counter = 10
      item.counter.should eq(10)
    end

    describe "#incrementing_<attr>!" do
      it "should increment atomic counter by default value" do
        client = stub_client
        AttributesSpec::IncrementModel.configure_client(client: client)
        client.stub_responses(
          :update_item,
          Aws::DynamoDB::Types::UpdateItemOutput.new(attributes: Aws::DynamoDB::Item{"counter" => 1_i64})
        )

        item = AttributesSpec::IncrementModel.new(id: 1)
        item.save!
        item.increment_counter!
        item.counter.should eq(1)
        api_requests(client)[1].params.to_json.should eq(
          %({"TableName":"TestTable","Key":{"id":{"N":"1"}},"UpdateExpression":"SET #n = #n + :i",) +
          %("ExpressionAttributeNames":{"#n":"counter"},"ExpressionAttributeValues":{":i":{"N":"1"}},) +
          %("ReturnValues":"UPDATED_NEW"})
        )
      end

      it "should increment the atomic counter by a custom value" do
        client = stub_client
        AttributesSpec::IncrementModel.configure_client(client: client)
        client.stub_responses(
          :update_item,
          Aws::DynamoDB::Types::UpdateItemOutput.new(attributes: Aws::DynamoDB::Item{"counter" => 2_i64})
        )

        item = AttributesSpec::IncrementModel.new(id: 1)
        item.save!
        item.increment_counter!(2)
        item.counter.should eq(2)
        api_requests(client)[1].params["ExpressionAttributeValues"][":i"]["N"].should eq("2")
      end

      it "will raise when incrementing on a dirty item" do
        AttributesSpec::IncrementModel.configure_client(client: stub_client)
        item = AttributesSpec::IncrementModel.new(id: 1)
        expect_raises(Aws::Record::Errors::RecordError, "Attributes need to be saved") do
          item.increment_counter!
        end
      end

      it "will raise when arg is not an integer" do
        expect_compile_error("increment_non_integer.cr", "to be Int, not String")
      end
    end
  end

  describe "inheritance support" do
    it "should have instances of child models with parent attributes " \
       "and an instance of parent model with its own attributes" do
      parent = AttributesSpec::ParentModel.new(id: 1, date: "2022-10-10", list: [] of Aws::DynamoDB::Value)
      child = AttributesSpec::ChildModel.new(
        id: 2, date: "2022-10-21", list: [1_i64, 2_i64, 3_i64] of Aws::DynamoDB::Value, body: "Hello"
      )
      child2 = AttributesSpec::ChildModel2.new(
        id: 3, date: "2022-10-31", list: [4_i64, 5_i64, 6_i64] of Aws::DynamoDB::Value, body2: "World"
      )

      parent.id.should eq(1)
      parent.date.should eq(Time.utc(2022, 10, 10))
      parent.list.should eq([] of Aws::DynamoDB::Value)
      parent.responds_to?(:body).should be_false
      parent.responds_to?(:body2).should be_false

      child.id.should eq(2)
      child.date.should eq(Time.utc(2022, 10, 21))
      child.list.should eq([1_i64, 2_i64, 3_i64] of Aws::DynamoDB::Value)
      child.body.should eq("Hello")
      child.responds_to?(:body2).should be_false

      child2.id.should eq(3)
      child2.date.should eq(Time.utc(2022, 10, 31))
      child2.list.should eq([4_i64, 5_i64, 6_i64] of Aws::DynamoDB::Value)
      child2.body2.should eq("World")
      child2.responds_to?(:body).should be_false
    end

    it "should let child model override attribute keys" do
      child = AttributesSpec::KeyOverrideChild.new(
        id: 1, rk: 1, date: "2022-10-21", list: [1_i64] of Aws::DynamoDB::Value, body: "foo"
      )
      child.id.should eq(1)
      child.rk.should eq(1)
      child.key_values.should eq(Aws::DynamoDB::Item{"id" => 1_i64, "rk" => 1_i64})
      AttributesSpec::KeyOverrideChild.keys.should eq({:hash => "id", :range => "rk"})
    end

    it "correctly passes default values to child model" do
      child = AttributesSpec::ChildModel.new(
        id: 1, date: "2022-10-21", list: [1_i64] of Aws::DynamoDB::Value, body: "foo"
      )
      child.test.should eq("test")
    end
  end
end

# Parity: 27/27 examples from spec/aws-record/record/attributes_spec.rb (aws-record 2.15.1)
