require "../spec_helper"

# The Ruby specs build anonymous classes with `Class.new { include Aws::Record }`; Crystal models are
# static, so each example group gets its own named model here.
module RecordSpec
  class UnitTestModel < Aws::Record::Base
  end

  class UnitTestModelTwo < Aws::Record::Base
    set_table_name "ExpectedTableName"
  end

  class ThroughputModel < Aws::Record::Base
    set_table_name "TestTable"
  end

  class TableExistsModel < Aws::Record::Base
    set_table_name "TestTable"
  end

  class TrackMutationsModel < Aws::Record::Base
    set_table_name "TestTable"
    string_attr :uuid, hash_key: true
    attr :mt, Aws::Record::Marshalers::StringMarshaler
  end

  class DefaultValueModel < Aws::Record::Base
    set_table_name "TestTable"
    string_attr :uuid, hash_key: true
    map_attr :things, default_value: Aws::DynamoDB::Item.new
  end

  class AttributeNamesModel < Aws::Record::Base
    set_table_name "TestTable"
    string_attr :uuid, hash_key: true
    string_attr :other_attr
  end

  class ParentTableModel < Aws::Record::Base
    set_table_name "ParentTable"
  end

  class ChildTableModel < ParentTableModel
  end

  class ChildTableOverrideModel < ParentTableModel
    set_table_name "ChildTable"
  end

  class ParentModel < Aws::Record::Base
  end

  class ChildModel < ParentModel
  end

  class TrackingParent < Aws::Record::Base
    integer_attr :id, hash_key: true
  end

  class TrackingChild < TrackingParent
    string_attr :foo
  end

  class OwnTrackingParent < Aws::Record::Base
    integer_attr :id, hash_key: true
  end

  class OwnTrackingChild < OwnTrackingParent
    string_attr :foo
  end
end

module OuterOne
  module OuterTwo
    class ClassTableName < Aws::Record::Base
    end
  end
end

private def table_output(status : String? = nil, read : Int64? = nil, write : Int64? = nil)
  Aws::DynamoDB::Types::DescribeTableOutput.new(
    table: Aws::DynamoDB::Types::TableDescription.new(
      table_status: status,
      provisioned_throughput: read || write ? Aws::DynamoDB::Types::ProvisionedThroughput.new(
        read_capacity_units: read, write_capacity_units: write
      ) : nil
    )
  )
end

describe "Record" do
  describe "#table_name" do
    it "should have an implied table name from the class name" do
      RecordSpec::UnitTestModel.table_name.should eq("RecordSpec_UnitTestModel")
    end

    it "should allow a custom table name to be specified" do
      RecordSpec::UnitTestModelTwo.table_name.should eq("ExpectedTableName")
    end

    it "should transform outer modules for default table name" do
      OuterOne::OuterTwo::ClassTableName.table_name.should eq("OuterOne_OuterTwo_ClassTableName")
    end
  end

  describe "#provisioned_throughput" do
    it "should fetch the provisioned throughput for the table on request" do
      client = stub_client
      client.stub_responses(:describe_table, table_output(read: 25_i64, write: 30_i64))
      RecordSpec::ThroughputModel.configure_client(client: client)

      RecordSpec::ThroughputModel.provisioned_throughput
        .should eq({read_capacity_units: 25_i64, write_capacity_units: 30_i64})
      api_requests(client)[0].input.as(Aws::DynamoDB::Types::DescribeTableInput)
        .table_name.should eq("TestTable")
    end

    it "should raise a TableDoesNotExist error if the table does not exist" do
      client = stub_client
      client.stub_responses(:describe_table, "ResourceNotFoundException")
      RecordSpec::ThroughputModel.configure_client(client: client)

      expect_raises(Aws::Record::Errors::TableDoesNotExist) { RecordSpec::ThroughputModel.provisioned_throughput }
    end
  end

  describe "#table_exists" do
    it "can check if the table exists" do
      client = stub_client
      client.stub_responses(:describe_table, table_output(status: "ACTIVE"))
      RecordSpec::TableExistsModel.configure_client(client: client)

      RecordSpec::TableExistsModel.table_exists?.should be_true
    end

    it "will not recognize a table as existing if it is not active" do
      client = stub_client
      client.stub_responses(:describe_table, table_output(status: "CREATING"))
      RecordSpec::TableExistsModel.configure_client(client: client)

      RecordSpec::TableExistsModel.table_exists?.should be_false
    end

    it "will answer false to #table_exists? if the table does not exist in DynamoDB" do
      client = stub_client
      client.stub_responses(:describe_table, "ResourceNotFoundException")
      RecordSpec::TableExistsModel.configure_client(client: client)

      RecordSpec::TableExistsModel.table_exists?.should be_false
    end
  end

  describe "#track_mutations" do
    it "is on by default" do
      RecordSpec::TrackMutationsModel.enable_mutation_tracking
      RecordSpec::TrackMutationsModel.mutation_tracking_enabled?.should be_true
    end

    it "can turn off mutation tracking globally for a model" do
      RecordSpec::TrackMutationsModel.disable_mutation_tracking
      RecordSpec::TrackMutationsModel.mutation_tracking_enabled?.should be_false
    ensure
      RecordSpec::TrackMutationsModel.enable_mutation_tracking
    end
  end

  describe "default_value" do
    it "uses a deep copy of the default_value" do
      RecordSpec::DefaultValueModel.new.things.try { |things| things["foo"] = "bar" }
      RecordSpec::DefaultValueModel.new.things.should eq(Aws::DynamoDB::Item.new)
    end
  end

  describe "attribute_names" do
    describe ".attribute_names" do
      it "returns the attribute names" do
        RecordSpec::AttributeNamesModel.attribute_names.should eq(["uuid", "other_attr"])
      end
    end

    describe "#attribute_names" do
      it "returns the attribute names" do
        RecordSpec::AttributeNamesModel.new.attribute_names.should eq(["uuid", "other_attr"])
      end
    end
  end

  describe "inheritance support for table name" do
    it "should have child model inherit table name from parent model if it is defined in parent model" do
      RecordSpec::ParentTableModel.table_name.should eq("ParentTable")
      RecordSpec::ChildTableModel.table_name.should eq("ParentTable")
    end

    it "should have child model override parent table name if defined in model" do
      RecordSpec::ParentTableModel.table_name.should eq("ParentTable")
      RecordSpec::ChildTableOverrideModel.table_name.should eq("ChildTable")
    end

    it "should have parent and child models maintain their default table names" do
      RecordSpec::ParentModel.table_name.should eq("RecordSpec_ParentModel")
      RecordSpec::ChildModel.table_name.should eq("RecordSpec_ChildModel")
    end
  end

  describe "inheritance support for track mutations" do
    it "should have child model inherit track mutations from parent model" do
      RecordSpec::TrackingParent.disable_mutation_tracking
      RecordSpec::TrackingParent.mutation_tracking_enabled?.should be_false
      RecordSpec::TrackingChild.mutation_tracking_enabled?.should be_false
    ensure
      RecordSpec::TrackingParent.enable_mutation_tracking
    end

    it "should have child model maintain its own track mutations if defined in model" do
      RecordSpec::OwnTrackingChild.disable_mutation_tracking
      RecordSpec::OwnTrackingParent.mutation_tracking_enabled?.should be_true
      RecordSpec::OwnTrackingChild.mutation_tracking_enabled?.should be_false
    ensure
      RecordSpec::OwnTrackingChild.enable_mutation_tracking
    end
  end
end

# Parity: 18/18 examples from spec/aws-record/record_spec.rb (aws-record 2.15.1)
