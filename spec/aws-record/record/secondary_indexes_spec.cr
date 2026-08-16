require "../../spec_helper"

module SecondaryIndexesSpec
  class TestModel < Aws::Record::Base
    set_table_name "TestTable"
    integer_attr :forum_id, hash_key: true
    integer_attr :post_id, range_key: true
    string_attr :forum_name
    string_attr :post_title
    integer_attr :author_id, database_attribute_name: "a_id"
    string_attr :author_name, database_attribute_name: "a_name"
    string_attr :post_body

    local_secondary_index :title, range_key: :post_title, projection: {projection_type: "ALL"}
    local_secondary_index :author, range_key: :author_id, projection: {projection_type: "ALL"}
    global_secondary_index :author, hash_key: :forum_name, range_key: :author_name,
      projection: {projection_type: "ALL"}
  end

  class ParentModel < Aws::Record::Base
    integer_attr :id, hash_key: true
    string_attr :name, range_key: true
    string_attr :message

    local_secondary_index :local_index, hash_key: :id, range_key: :message
    global_secondary_index :global_index, hash_key: :name, range_key: :message
  end

  class ChildModel < ParentModel
    string_attr :foo
    string_attr :bar
  end

  class OverridingChildModel < ParentModel
    string_attr :foo
    string_attr :bar

    local_secondary_index :local_index, hash_key: :id, range_key: :foo
    global_secondary_index :global_index, hash_key: :bar, range_key: :foo
  end
end

describe "SecondaryIndexes" do
  describe "Local Secondary Index" do
    describe "#local_secondary_index" do
      it "allows you to define a local secondary index on the model" do
        SecondaryIndexesSpec::TestModel.local_secondary_indexes["title"]?.should_not be_nil
      end

      it "requires that a range key is provided" do
        expect_compile_error("lsi_missing_range_key.cr", "Local Secondary Indexes require a hash and range key!")
      end

      it "requires use of an attribute that exists in the model" do
        expect_compile_error("lsi_missing_attribute.cr", "not present in model attributes")
      end
    end

    describe "#local_secondary_indexes_for_migration" do
      it "correctly translates database names for migration" do
        migration = SecondaryIndexesSpec::TestModel.local_secondary_indexes_for_migration.should_not be_nil
        migration.size.should eq(2)
        author = migration.find { |index| index.index_name == "author" }.should_not be_nil
        author.to_wire.to_json.should eq(
          %({"IndexName":"author","KeySchema":[{"AttributeName":"forum_id","KeyType":"HASH"},) +
          %({"AttributeName":"a_id","KeyType":"RANGE"}],"Projection":{"ProjectionType":"ALL"}})
        )
      end
    end
  end

  describe "Global Secondary Indexes" do
    describe "#global_secondary_index" do
      it "allows you to define a global secondary index on the model" do
        SecondaryIndexesSpec::TestModel.global_secondary_indexes["author"]?.should_not be_nil
      end

      it "requires that a hash key is provided" do
        expect_compile_error("gsi_missing_hash_key.cr", "Global Secondary Indexes require at least a hash key!")
      end

      it "requires that the hash key exists in the model" do
        expect_compile_error("gsi_missing_hash_attribute.cr", "not present in model attributes")
      end

      it "requires that the range key exists in the model" do
        expect_compile_error("gsi_missing_range_attribute.cr", "not present in model attributes")
      end
    end

    describe "#global_secondary_indexes_for_migration" do
      it "correctly translates database names for migration" do
        migration = SecondaryIndexesSpec::TestModel.global_secondary_indexes_for_migration.should_not be_nil
        migration.size.should eq(1)
        migration.first.to_wire.to_json.should eq(
          %({"IndexName":"author","KeySchema":[{"AttributeName":"forum_name","KeyType":"HASH"},) +
          %({"AttributeName":"a_name","KeyType":"RANGE"}],"Projection":{"ProjectionType":"ALL"}})
        )
      end
    end
  end
end

describe "inheritance support" do
  it "should have child model inherit secondary indexes from parent model" do
    SecondaryIndexesSpec::ChildModel.local_secondary_indexes
      .should eq(SecondaryIndexesSpec::ParentModel.local_secondary_indexes)
    SecondaryIndexesSpec::ChildModel.global_secondary_indexes
      .should eq(SecondaryIndexesSpec::ParentModel.global_secondary_indexes)
  end

  it "allows the child model override parent indexes" do
    local = SecondaryIndexesSpec::OverridingChildModel.local_secondary_indexes
    local.keys.should eq(["local_index"])
    local["local_index"].hash_key.should eq("id")
    local["local_index"].range_key.should eq("foo")

    global = SecondaryIndexesSpec::OverridingChildModel.global_secondary_indexes
    global.keys.should eq(["global_index"])
    global["global_index"].hash_key.should eq("bar")
    global["global_index"].range_key.should eq("foo")
  end
end

# Parity: 11/11 examples from spec/aws-record/record/secondary_indexes_spec.rb (aws-record 2.15.1)
