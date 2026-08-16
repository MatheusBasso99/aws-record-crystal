require "../../spec_helper"

class TestModel < Aws::Record::Base
  string_attr :hk, hash_key: true
  string_attr :rk, range_key: true
end

class TestModelWithGsi < Aws::Record::Base
  string_attr :hk, hash_key: true
  string_attr :rk, range_key: true
  string_attr :gsi_pk
  string_attr :gsi_sk
  string_attr :a
  string_attr :b
  string_attr :c

  global_secondary_index :gsi, hash_key: :gsi_pk, range_key: :gsi_sk,
    projection: {projection_type: "INCLUDE", non_key_attributes: ["c", "b", "a"]}
end

class TestModelWithGsi2 < Aws::Record::Base
  string_attr :hk, hash_key: true
  string_attr :rk, range_key: true
  string_attr :gsi_sk

  global_secondary_index :gsi, hash_key: :hk, range_key: :gsi_sk, projection: {projection_type: "ALL"}
end

class TestModelWithGsi3 < Aws::Record::Base
  string_attr :hk, hash_key: true
  string_attr :rk, range_key: true
  string_attr :gsi_pk
  string_attr :gsi_sk

  global_secondary_index :gsi, hash_key: :hk, range_key: :gsi_sk, projection: {projection_type: "ALL"}
  global_secondary_index :gsi2, hash_key: :gsi_pk, range_key: :gsi_sk, projection: {projection_type: "ALL"}
end

class TestModelWithTtl < Aws::Record::Base
  string_attr :hk, hash_key: true
  string_attr :rk, range_key: true
  epoch_time_attr :ttl, database_attribute_name: "TimeToLive"
end

module TableConfigSpec
  extend self

  # The key schema every model in this spec has.
  def key_schema : Array(Aws::DynamoDB::Types::KeySchemaElement)
    [
      Aws::DynamoDB::Types::KeySchemaElement.new(attribute_name: "hk", key_type: "HASH"),
      Aws::DynamoDB::Types::KeySchemaElement.new(attribute_name: "rk", key_type: "RANGE"),
    ]
  end

  def definitions(*names : String) : Array(Aws::DynamoDB::Types::AttributeDefinition)
    result = [] of Aws::DynamoDB::Types::AttributeDefinition
    names.each { |name| result << definition(name) }
    result
  end

  def definition(name : String, type : String = "S") : Aws::DynamoDB::Types::AttributeDefinition
    Aws::DynamoDB::Types::AttributeDefinition.new(attribute_name: name, attribute_type: type)
  end

  def throughput(read : Int64, write : Int64) : Aws::DynamoDB::Types::ProvisionedThroughput
    Aws::DynamoDB::Types::ProvisionedThroughput.new(
      read_capacity_units: read, write_capacity_units: write, number_of_decreases_today: 0_i64
    )
  end

  def index(name : String, hash_key : String, range_key : String,
            projection_type : String = "ALL",
            non_key_attributes : Array(String)? = nil,
            provisioned_throughput : Aws::DynamoDB::Types::ProvisionedThroughput? = nil) \
     : Aws::DynamoDB::Types::GlobalSecondaryIndex
      Aws::DynamoDB::Types::GlobalSecondaryIndex.new(
        index_name: name,
        key_schema: [
          Aws::DynamoDB::Types::KeySchemaElement.new(attribute_name: hash_key, key_type: "HASH"),
          Aws::DynamoDB::Types::KeySchemaElement.new(attribute_name: range_key, key_type: "RANGE"),
        ],
        projection: Aws::DynamoDB::Types::Projection.new(
          projection_type: projection_type, non_key_attributes: non_key_attributes
        ),
        provisioned_throughput: provisioned_throughput
      )
    end

  def described(table_name : String, *, attribute_names : Array(String) = ["hk", "rk"],
                read : Int64? = 1_i64, write : Int64? = 1_i64, billing_mode : String? = nil,
                indexes : Array(Aws::DynamoDB::Types::GlobalSecondaryIndex)? = nil,
                status : String = "ACTIVE") : Aws::DynamoDB::Types::DescribeTableOutput
    Aws::DynamoDB::Types::DescribeTableOutput.new(
      table: Aws::DynamoDB::Types::TableDescription.new(
        table_name: table_name,
        table_status: status,
        attribute_definitions: attribute_names.map { |name| definition(name) },
        key_schema: key_schema,
        provisioned_throughput: read || write ? throughput(read || 0_i64, write || 0_i64) : nil,
        billing_mode_summary: billing_mode ? summary(billing_mode) : nil,
        global_secondary_indexes: indexes
      )
    )
  end

  def summary(mode : String) : Aws::DynamoDB::Types::BillingModeSummary
    Aws::DynamoDB::Types::BillingModeSummary.new(billing_mode: mode)
  end

  def active : Aws::DynamoDB::Types::DescribeTableOutput
    Aws::DynamoDB::Types::DescribeTableOutput.new(
      table: Aws::DynamoDB::Types::TableDescription.new(table_status: "ACTIVE")
    )
  end

  def ttl(status : String?, attribute : String? = nil) : Aws::DynamoDB::Types::DescribeTimeToLiveOutput
    Aws::DynamoDB::Types::DescribeTimeToLiveOutput.new(
      time_to_live_description: Aws::DynamoDB::Types::TimeToLiveDescription.new(
        time_to_live_status: status, attribute_name: attribute
      )
    )
  end
end

private def stub_options : NamedTuple(stub_responses: Bool, region: String)
  {stub_responses: true, region: "us-east-1"}
end

private def config_for(model : Aws::Record::Base.class,
                       read : Int32? = 1, write : Int32? = 1) : Aws::Record::TableConfig
  Aws::Record::TableConfig.define do |table|
    table.model_class model
    table.read_capacity_units read if read
    table.write_capacity_units write if write
    table.client_options(**stub_options)
  end
end

describe Aws::Record::TableConfig do
  it "accepts a minimal set of table configuration inputs" do
    config_for(TestModel).client.config.stub_responses?.should be_true
  end

  it "can be given a client instead of client options" do
    client = stub_client
    config = Aws::Record::TableConfig.define do |table|
      table.model_class TestModel
      table.read_capacity_units 1
      table.write_capacity_units 1
      table.client_options client
    end
    config.client.should be(client)
    client.config.user_agent_frameworks.should eq(["aws-record"])
  end

  describe "global secondary indexes" do
    it "accepts with capacity settings defined" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModelWithGsi
        table.read_capacity_units 2
        table.write_capacity_units 2
        table.global_secondary_index(:gsi) do |index|
          index.read_capacity_units 1
          index.write_capacity_units 1
        end
        table.client_options(**stub_options)
      end
      config.client.should be_a(Aws::DynamoDB::Client)
    end

    it "accepts without capacity settings defined" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModelWithGsi
        table.global_secondary_index(:gsi)
        table.client_options(**stub_options)
      end
      config.client.should be_a(Aws::DynamoDB::Client)
    end
  end

  describe "#migrate!" do
    it "will attempt to create the remote table if it does not exist" do
      config = config_for(TestModel)
      config.client.stub_responses(:describe_table, "ResourceNotFoundException", TableConfigSpec.active)
      config.migrate!

      api_requests(config.client)[1].params.should eq(
        JSON.parse(
          %({"TableName":"TestModel",) +
          %("AttributeDefinitions":[{"AttributeName":"hk","AttributeType":"S"},) +
          %({"AttributeName":"rk","AttributeType":"S"}],) +
          %("KeySchema":[{"AttributeName":"hk","KeyType":"HASH"},{"AttributeName":"rk","KeyType":"RANGE"}],) +
          %("ProvisionedThroughput":{"ReadCapacityUnits":1,"WriteCapacityUnits":1}})
        )
      )
    end

    it "will update an existing table" do
      config = config_for(TestModel, read: 2, write: 1)
      config.client.stub_responses(:describe_table, TableConfigSpec.described("TestModel"), TableConfigSpec.active)
      config.migrate!

      api_requests(config.client)[1].params.should eq(
        JSON.parse(
          %({"TableName":"TestModel",) +
          %("ProvisionedThroughput":{"ReadCapacityUnits":2,"WriteCapacityUnits":1}})
        )
      )
    end

    it "will validate required configuration values" do
      config = Aws::Record::TableConfig.define(&.client_options(**stub_options))
      expect_raises(
        Aws::Record::Errors::MissingRequiredConfiguration,
        "Missing: model_class, read_capacity_units, write_capacity_units"
      ) { config.migrate! }
    end

    it "will validate model_class configuration" do
      config = Aws::Record::TableConfig.define do |table|
        table.read_capacity_units 1
        table.write_capacity_units 1
        table.client_options(**stub_options)
      end
      expect_raises(Aws::Record::Errors::MissingRequiredConfiguration, "Missing: model_class") { config.migrate! }
    end

    it "will validate provisioned throughput configuration values" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModel
        table.client_options(**stub_options)
      end
      expect_raises(
        Aws::Record::Errors::MissingRequiredConfiguration,
        "Missing: read_capacity_units, write_capacity_units"
      ) { config.migrate! }
    end

    describe "Global Secondary Indexes" do
      it "can create a new table with global secondary indexes" do
        config = Aws::Record::TableConfig.define do |table|
          table.model_class TestModelWithGsi
          table.read_capacity_units 2
          table.write_capacity_units 2
          table.global_secondary_index(:gsi) do |index|
            index.read_capacity_units 1
            index.write_capacity_units 1
          end
          table.client_options(**stub_options)
        end
        config.client.stub_responses(:describe_table, "ResourceNotFoundException", TableConfigSpec.active)
        config.migrate!

        api_requests(config.client)[1].params.should eq(
          JSON.parse(
            %({"TableName":"TestModelWithGsi",) +
            %("AttributeDefinitions":[{"AttributeName":"hk","AttributeType":"S"},) +
            %({"AttributeName":"rk","AttributeType":"S"},{"AttributeName":"gsi_pk","AttributeType":"S"},) +
            %({"AttributeName":"gsi_sk","AttributeType":"S"}],) +
            %("KeySchema":[{"AttributeName":"hk","KeyType":"HASH"},{"AttributeName":"rk","KeyType":"RANGE"}],) +
            %("GlobalSecondaryIndexes":[{"IndexName":"gsi",) +
            %("KeySchema":[{"AttributeName":"gsi_pk","KeyType":"HASH"},) +
            %({"AttributeName":"gsi_sk","KeyType":"RANGE"}],) +
            %("Projection":{"ProjectionType":"INCLUDE","NonKeyAttributes":["c","b","a"]},) +
            %("ProvisionedThroughput":{"ReadCapacityUnits":1,"WriteCapacityUnits":1}}],) +
            %("ProvisionedThroughput":{"ReadCapacityUnits":2,"WriteCapacityUnits":2}})
          )
        )
      end

      it "can update a table to add global secondary indexes" do
        config = Aws::Record::TableConfig.define do |table|
          table.model_class TestModelWithGsi
          table.read_capacity_units 2
          table.write_capacity_units 2
          table.global_secondary_index(:gsi) do |index|
            index.read_capacity_units 1
            index.write_capacity_units 1
          end
          table.client_options(**stub_options)
        end
        config.client.stub_responses(
          :describe_table,
          TableConfigSpec.described("TestModelWithGsi", read: 2_i64, write: 2_i64),
          TableConfigSpec.active
        )
        config.migrate!

        api_requests(config.client)[1].params.should eq(
          JSON.parse(
            %({"TableName":"TestModelWithGsi",) +
            %("AttributeDefinitions":[{"AttributeName":"gsi_pk","AttributeType":"S"},) +
            %({"AttributeName":"gsi_sk","AttributeType":"S"}],) +
            %("GlobalSecondaryIndexUpdates":[{"Create":{"IndexName":"gsi",) +
            %("KeySchema":[{"AttributeName":"gsi_pk","KeyType":"HASH"},) +
            %({"AttributeName":"gsi_sk","KeyType":"RANGE"}],) +
            %("Projection":{"ProjectionType":"INCLUDE","NonKeyAttributes":["c","b","a"]},) +
            %("ProvisionedThroughput":{"ReadCapacityUnits":1,"WriteCapacityUnits":1}}}]})
          )
        )
      end

      it "separates throughput and index updates" do
        config = Aws::Record::TableConfig.define do |table|
          table.model_class TestModelWithGsi
          table.read_capacity_units 2
          table.write_capacity_units 2
          table.global_secondary_index(:gsi) do |index|
            index.read_capacity_units 1
            index.write_capacity_units 1
          end
          table.client_options(**stub_options)
        end
        config.client.stub_responses(
          :describe_table,
          TableConfigSpec.described("TestModelWithGsi"),
          TableConfigSpec.active
        )
        config.migrate!

        requests = api_requests(config.client)
        requests[1].params.should eq(
          JSON.parse(
            %({"TableName":"TestModelWithGsi",) +
            %("ProvisionedThroughput":{"ReadCapacityUnits":2,"WriteCapacityUnits":2}})
          )
        )
        requests[3].params["GlobalSecondaryIndexUpdates"][0]["Create"]["IndexName"].should eq("gsi")
        requests[3].params["AttributeDefinitions"].as_a.size.should eq(2)
      end

      it "correctly reuses attribute definitions during gsi creation" do
        config = Aws::Record::TableConfig.define do |table|
          table.model_class TestModelWithGsi2
          table.read_capacity_units 2
          table.write_capacity_units 2
          table.global_secondary_index(:gsi) do |index|
            index.read_capacity_units 1
            index.write_capacity_units 1
          end
          table.client_options(**stub_options)
        end
        config.client.stub_responses(
          :describe_table,
          TableConfigSpec.described("TestModelWithGsi2", read: 2_i64, write: 2_i64),
          TableConfigSpec.active
        )
        config.migrate!

        # `hk` is already a key attribute, so only `gsi_sk` is added.
        api_requests(config.client)[1].params["AttributeDefinitions"].should eq(
          JSON.parse(%([{"AttributeName":"hk","AttributeType":"S"},{"AttributeName":"gsi_sk","AttributeType":"S"}]))
        )
      end

      it "can update a table to modify a global secondary index" do
        config = Aws::Record::TableConfig.define do |table|
          table.model_class TestModelWithGsi2
          table.read_capacity_units 2
          table.write_capacity_units 2
          table.global_secondary_index(:gsi) do |index|
            index.read_capacity_units 3
            index.write_capacity_units 3
          end
          table.client_options(**stub_options)
        end
        config.client.stub_responses(
          :describe_table,
          TableConfigSpec.described(
            "TestModelWithGsi2",
            attribute_names: ["hk", "rk", "gsi_sk"],
            read: 2_i64, write: 2_i64,
            indexes: [TableConfigSpec.index(
              "gsi", "hk", "gsi_sk",
              provisioned_throughput: TableConfigSpec.throughput(1_i64, 1_i64)
            )]
          ),
          TableConfigSpec.active
        )
        config.migrate!

        api_requests(config.client)[1].params.should eq(
          JSON.parse(
            %({"TableName":"TestModelWithGsi2","GlobalSecondaryIndexUpdates":[{"Update":{"IndexName":"gsi",) +
            %("ProvisionedThroughput":{"ReadCapacityUnits":3,"WriteCapacityUnits":3}}}]})
          )
        )
      end

      it "can handle multiple global secondary index updates at once" do
        config = Aws::Record::TableConfig.define do |table|
          table.model_class TestModelWithGsi3
          table.read_capacity_units 2
          table.write_capacity_units 2
          table.global_secondary_index(:gsi) do |index|
            index.read_capacity_units 3
            index.write_capacity_units 3
          end
          table.global_secondary_index(:gsi2) do |index|
            index.read_capacity_units 4
            index.write_capacity_units 4
          end
          table.client_options(**stub_options)
        end
        config.client.stub_responses(
          :describe_table,
          TableConfigSpec.described(
            "TestModelWithGsi3",
            attribute_names: ["hk", "rk", "gsi_sk"],
            read: 2_i64, write: 2_i64,
            indexes: [TableConfigSpec.index(
              "gsi", "hk", "gsi_sk",
              provisioned_throughput: TableConfigSpec.throughput(1_i64, 1_i64)
            )]
          ),
          TableConfigSpec.active
        )
        config.migrate!

        updates = api_requests(config.client)[1].params["GlobalSecondaryIndexUpdates"].as_a
        updates.size.should eq(2)
        updates[0]["Create"]["IndexName"].should eq("gsi2")
        updates[1]["Update"]["IndexName"].should eq("gsi")
        updates[1]["Update"]["ProvisionedThroughput"]["ReadCapacityUnits"].should eq(3)
      end
    end
  end

  describe "#compatible?" do
    it "compares against a #describe_table call" do
      config = config_for(TestModel)
      config.client.stub_responses(:describe_table, TableConfigSpec.described("TestModel"))
      config.compatible?.should be_true
    end

    it "fails when a configured value does not match" do
      config = config_for(TestModel)
      config.client.stub_responses(:describe_table, TableConfigSpec.described("TestModel", read: 2_i64))
      config.compatible?.should be_false
    end

    it "fails when the remote model does not match" do
      config = config_for(TestModel)
      config.client.stub_responses(
        :describe_table,
        Aws::DynamoDB::Types::DescribeTableOutput.new(
          table: Aws::DynamoDB::Types::TableDescription.new(
            table_name: "TestModel",
            attribute_definitions: TableConfigSpec.definitions("hashkey", "rk"),
            key_schema: [
              Aws::DynamoDB::Types::KeySchemaElement.new(attribute_name: "hashkey", key_type: "HASH"),
              Aws::DynamoDB::Types::KeySchemaElement.new(attribute_name: "rk", key_type: "RANGE"),
            ],
            provisioned_throughput: TableConfigSpec.throughput(1_i64, 1_i64)
          )
        )
      )
      config.compatible?.should be_false
    end

    it "matches with a superset of attribute definitions" do
      config = config_for(TestModel)
      config.client.stub_responses(
        :describe_table, TableConfigSpec.described("TestModel", attribute_names: ["hk", "rk", "extra"])
      )
      config.compatible?.should be_true
    end

    it "returns false if the table does not exist" do
      config = config_for(TestModel)
      config.client.stub_responses(:describe_table, "ResourceNotFoundException")
      config.compatible?.should be_false
    end

    it "returns false if a global secondary index is missing" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModelWithGsi2
        table.read_capacity_units 2
        table.write_capacity_units 2
        table.global_secondary_index(:gsi) do |index|
          index.read_capacity_units 1
          index.write_capacity_units 1
        end
        table.client_options(**stub_options)
      end
      config.client.stub_responses(
        :describe_table,
        TableConfigSpec.described("TestModelWithGsi2", attribute_names: ["hk", "rk", "gsi_sk"],
          read: 2_i64, write: 2_i64)
      )
      config.compatible?.should be_false
    end

    it "returns true if global secondary indexes are present and match" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModelWithGsi2
        table.read_capacity_units 2
        table.write_capacity_units 2
        table.global_secondary_index(:gsi) do |index|
          index.read_capacity_units 1
          index.write_capacity_units 1
        end
        table.client_options(**stub_options)
      end
      config.client.stub_responses(
        :describe_table,
        TableConfigSpec.described(
          "TestModelWithGsi2", attribute_names: ["hk", "rk", "gsi_sk"], read: 2_i64, write: 2_i64,
          indexes: [TableConfigSpec.index(
            "gsi", "hk", "gsi_sk", provisioned_throughput: TableConfigSpec.throughput(1_i64, 1_i64)
          )]
        )
      )
      config.compatible?.should be_true
    end

    it "returns true if superset of global secondary indexes are present" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModelWithGsi2
        table.read_capacity_units 2
        table.write_capacity_units 2
        table.global_secondary_index(:gsi) do |index|
          index.read_capacity_units 1
          index.write_capacity_units 1
        end
        table.client_options(**stub_options)
      end
      config.client.stub_responses(
        :describe_table,
        TableConfigSpec.described(
          "TestModelWithGsi2", attribute_names: ["hk", "rk", "gsi_sk", "extra"], read: 2_i64, write: 2_i64,
          indexes: [
            TableConfigSpec.index(
              "gsi", "hk", "gsi_sk", provisioned_throughput: TableConfigSpec.throughput(1_i64, 1_i64)
            ),
            TableConfigSpec.index(
              "extra_index", "hk", "extra", provisioned_throughput: TableConfigSpec.throughput(1_i64, 1_i64)
            ),
          ]
        )
      )
      config.compatible?.should be_true
    end

    it "returns false if there is an attribute definition mismatch" do
      config = config_for(TestModel)
      config.client.stub_responses(
        :describe_table,
        Aws::DynamoDB::Types::DescribeTableOutput.new(
          table: Aws::DynamoDB::Types::TableDescription.new(
            table_name: "TestModel",
            attribute_definitions: [
              Aws::DynamoDB::Types::AttributeDefinition.new(attribute_name: "hk", attribute_type: "N"),
              Aws::DynamoDB::Types::AttributeDefinition.new(attribute_name: "rk", attribute_type: "S"),
            ],
            key_schema: TableConfigSpec.key_schema,
            provisioned_throughput: TableConfigSpec.throughput(1_i64, 1_i64)
          )
        )
      )
      config.compatible?.should be_false
    end
  end

  describe "#exact_match?" do
    it "compares against a #describe_table call" do
      config = config_for(TestModel)
      config.client.stub_responses(:describe_table, TableConfigSpec.described("TestModel"))
      config.client.stub_responses(:describe_time_to_live, TableConfigSpec.ttl(nil))
      config.exact_match?.should be_true
    end

    it "fails when a configured value does not match" do
      config = config_for(TestModel)
      config.client.stub_responses(:describe_table, TableConfigSpec.described("TestModel", read: 2_i64))
      config.exact_match?.should be_false
    end

    it "fails when the remote model does not match" do
      config = config_for(TestModel)
      config.client.stub_responses(
        :describe_table,
        TableConfigSpec.described("TestModel", attribute_names: ["hashkey", "rk"])
      )
      config.exact_match?.should be_false
    end

    it "does not match with a superset of attribute definitions" do
      config = config_for(TestModel)
      config.client.stub_responses(
        :describe_table, TableConfigSpec.described("TestModel", attribute_names: ["hk", "rk", "extra"])
      )
      config.exact_match?.should be_false
    end

    it "returns false if the table does not exist" do
      config = config_for(TestModel)
      config.client.stub_responses(:describe_table, "ResourceNotFoundException")
      config.exact_match?.should be_false
    end

    it "returns false if a global secondary index is missing" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModelWithGsi2
        table.read_capacity_units 2
        table.write_capacity_units 2
        table.global_secondary_index(:gsi) do |index|
          index.read_capacity_units 1
          index.write_capacity_units 1
        end
        table.client_options(**stub_options)
      end
      config.client.stub_responses(
        :describe_table,
        TableConfigSpec.described("TestModelWithGsi2", attribute_names: ["hk", "rk", "gsi_sk"],
          read: 2_i64, write: 2_i64)
      )
      config.exact_match?.should be_false
    end

    it "returns true if global secondary indexes are present and match" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModelWithGsi2
        table.read_capacity_units 2
        table.write_capacity_units 2
        table.global_secondary_index(:gsi) do |index|
          index.read_capacity_units 1
          index.write_capacity_units 1
        end
        table.client_options(**stub_options)
      end
      config.client.stub_responses(
        :describe_table,
        TableConfigSpec.described(
          "TestModelWithGsi2", attribute_names: ["hk", "rk", "gsi_sk"], read: 2_i64, write: 2_i64,
          indexes: [TableConfigSpec.index(
            "gsi", "hk", "gsi_sk", provisioned_throughput: TableConfigSpec.throughput(1_i64, 1_i64)
          )]
        )
      )
      config.client.stub_responses(:describe_time_to_live, TableConfigSpec.ttl(nil))
      config.exact_match?.should be_true
    end

    it "returns false if superset of global secondary indexes present" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModelWithGsi2
        table.read_capacity_units 2
        table.write_capacity_units 2
        table.global_secondary_index(:gsi) do |index|
          index.read_capacity_units 1
          index.write_capacity_units 1
        end
        table.client_options(**stub_options)
      end
      config.client.stub_responses(
        :describe_table,
        TableConfigSpec.described(
          "TestModelWithGsi2", attribute_names: ["hk", "rk", "gsi_sk"], read: 2_i64, write: 2_i64,
          indexes: [
            TableConfigSpec.index(
              "gsi", "hk", "gsi_sk", provisioned_throughput: TableConfigSpec.throughput(1_i64, 1_i64)
            ),
            TableConfigSpec.index(
              "extra_index", "hk", "gsi_sk", provisioned_throughput: TableConfigSpec.throughput(1_i64, 1_i64)
            ),
          ]
        )
      )
      config.exact_match?.should be_false
    end

    it "returns false if there is an attribute definition mismatch" do
      config = config_for(TestModel)
      config.client.stub_responses(
        :describe_table,
        Aws::DynamoDB::Types::DescribeTableOutput.new(
          table: Aws::DynamoDB::Types::TableDescription.new(
            table_name: "TestModel",
            attribute_definitions: [
              Aws::DynamoDB::Types::AttributeDefinition.new(attribute_name: "hk", attribute_type: "N"),
              Aws::DynamoDB::Types::AttributeDefinition.new(attribute_name: "rk", attribute_type: "S"),
            ],
            key_schema: TableConfigSpec.key_schema,
            provisioned_throughput: TableConfigSpec.throughput(1_i64, 1_i64)
          )
        )
      )
      config.exact_match?.should be_false
    end
  end

  describe "TTL Attributes" do
    it "raises an exception when TTL is applied to a missing attribute" do
      expect_raises(ArgumentError, "Invalid attribute bizarro_ttl") do
        Aws::Record::TableConfig.define do |table|
          table.model_class TestModelWithTtl
          table.read_capacity_units 1
          table.write_capacity_units 1
          table.ttl_attribute :bizarro_ttl
          table.client_options(**stub_options)
        end
      end
    end

    it "applies TTL attribute settings" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModelWithTtl
        table.read_capacity_units 1
        table.write_capacity_units 1
        table.ttl_attribute :ttl
        table.client_options(**stub_options)
      end
      config.client.stub_responses(:describe_table, "ResourceNotFoundException", TableConfigSpec.active)
      config.client.stub_responses(:describe_time_to_live, TableConfigSpec.ttl("DISABLED"))
      config.migrate!

      requests = api_requests(config.client)
      requests[1].params["TableName"].should eq("TestModelWithTtl")
      requests[4].params.should eq(
        JSON.parse(
          %({"TableName":"TestModelWithTtl",) +
          %("TimeToLiveSpecification":{"Enabled":true,"AttributeName":"TimeToLive"}})
        )
      )
    end
  end

  describe "Pay Per Request Capacity" do
    it "accepts billing mode in table config" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModel
        table.billing_mode "PAY_PER_REQUEST"
        table.client_options(**stub_options)
      end
      config.client.should be_a(Aws::DynamoDB::Client)
    end

    it "accepts billing mode in table config with a GSI" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModelWithGsi
        table.billing_mode "PAY_PER_REQUEST"
        table.client_options(**stub_options)
      end
      config.client.should be_a(Aws::DynamoDB::Client)
    end

    it "can create a table with ppr billing" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModel
        table.billing_mode "PAY_PER_REQUEST"
        table.client_options(**stub_options)
      end
      config.client.stub_responses(:describe_table, "ResourceNotFoundException", TableConfigSpec.active)
      config.migrate!

      api_requests(config.client)[1].params["BillingMode"].should eq("PAY_PER_REQUEST")
      api_requests(config.client)[1].params["ProvisionedThroughput"]?.should be_nil
    end

    it "confirms compatibility of tables with PPR billing" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModel
        table.billing_mode "PAY_PER_REQUEST"
        table.client_options(**stub_options)
      end
      config.client.stub_responses(
        :describe_table,
        TableConfigSpec.described("TestModel", read: nil, write: nil, billing_mode: "PAY_PER_REQUEST")
      )
      config.compatible?.should be_true
    end

    it "registers incompatible when remote is provisioned" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModel
        table.billing_mode "PAY_PER_REQUEST"
        table.client_options(**stub_options)
      end
      config.client.stub_responses(:describe_table, TableConfigSpec.described("TestModel"))
      config.compatible?.should be_false
    end

    it "registers incompatible when remote is ppr" do
      config = config_for(TestModel)
      config.client.stub_responses(
        :describe_table,
        TableConfigSpec.described("TestModel", read: nil, write: nil, billing_mode: "PAY_PER_REQUEST")
      )
      config.compatible?.should be_false
    end

    it "can transition from provisioned to ppr billing" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModel
        table.billing_mode "PAY_PER_REQUEST"
        table.client_options(**stub_options)
      end
      config.client.stub_responses(
        :describe_table, TableConfigSpec.described("TestModel"), TableConfigSpec.active
      )
      config.migrate!

      api_requests(config.client)[1].params.should eq(
        JSON.parse(%({"TableName":"TestModel","BillingMode":"PAY_PER_REQUEST"}))
      )
    end

    it "can transition from ppr to provisioned billing" do
      config = config_for(TestModel, read: 2, write: 2)
      config.client.stub_responses(
        :describe_table,
        TableConfigSpec.described("TestModel", read: nil, write: nil, billing_mode: "PAY_PER_REQUEST"),
        TableConfigSpec.active
      )
      config.migrate!

      api_requests(config.client)[1].params.should eq(
        JSON.parse(
          %({"TableName":"TestModel","BillingMode":"PROVISIONED",) +
          %("ProvisionedThroughput":{"ReadCapacityUnits":2,"WriteCapacityUnits":2}})
        )
      )
    end

    it "can create ppr global secondary indexes" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModelWithGsi2
        table.billing_mode "PAY_PER_REQUEST"
        table.client_options(**stub_options)
      end
      config.client.stub_responses(:describe_table, "ResourceNotFoundException", TableConfigSpec.active)
      config.migrate!

      index = api_requests(config.client)[1].params["GlobalSecondaryIndexes"][0]
      index["IndexName"].should eq("gsi")
      index["ProvisionedThroughput"]?.should be_nil
    end

    it "can transition from ppr to provisioned billing for global secondary indexes" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModelWithGsi2
        table.billing_mode "PAY_PER_REQUEST"
        table.client_options(**stub_options)
      end
      config.client.stub_responses(
        :describe_table,
        TableConfigSpec.described(
          "TestModelWithGsi2", attribute_names: ["hk", "rk", "gsi_pk", "gsi_sk"],
          read: 2_i64, write: 1_i64,
          indexes: [Aws::DynamoDB::Types::GlobalSecondaryIndex.new(
            index_name: "gsi",
            key_schema: [
              Aws::DynamoDB::Types::KeySchemaElement.new(attribute_name: "gsi_sk", key_type: "RANGE"),
              Aws::DynamoDB::Types::KeySchemaElement.new(attribute_name: "gsi_pk", key_type: "HASH"),
            ],
            projection: Aws::DynamoDB::Types::Projection.new(
              projection_type: "INCLUDE", non_key_attributes: ["a", "b", "c"]
            ),
            index_status: "ACTIVE",
            backfilling: false,
            item_count: 0_i64,
            provisioned_throughput: TableConfigSpec.throughput(2_i64, 1_i64)
          )]
        ),
        TableConfigSpec.active
      )
      config.migrate!

      api_requests(config.client)[1].params.should eq(
        JSON.parse(%({"TableName":"TestModelWithGsi2","BillingMode":"PAY_PER_REQUEST"}))
      )
    end

    it "can transition from ppr to provisioned billing for global secondary indexes" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModelWithGsi2
        table.read_capacity_units 2
        table.write_capacity_units 2
        table.global_secondary_index(:gsi) do |index|
          index.read_capacity_units 2
          index.write_capacity_units 2
        end
        table.client_options(**stub_options)
      end
      config.client.stub_responses(
        :describe_table,
        TableConfigSpec.described(
          "TestModelWithGsi2", attribute_names: ["hk", "rk", "gsi_sk"], read: nil, write: nil,
          billing_mode: "PAY_PER_REQUEST",
          indexes: [TableConfigSpec.index("gsi", "hk", "gsi_sk")]
        ),
        TableConfigSpec.active
      )
      config.migrate!

      api_requests(config.client)[1].params.should eq(
        JSON.parse(
          %({"TableName":"TestModelWithGsi2","BillingMode":"PROVISIONED",) +
          %("ProvisionedThroughput":{"ReadCapacityUnits":2,"WriteCapacityUnits":2},) +
          %("GlobalSecondaryIndexUpdates":[{"Update":{"IndexName":"gsi",) +
          %("ProvisionedThroughput":{"ReadCapacityUnits":2,"WriteCapacityUnits":2}}}]})
        )
      )
    end

    it "will raise an argument error when given a nonsense billing mode" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModel
        table.billing_mode "FREE_LUNCH"
        table.client_options(**stub_options)
      end
      config.client.stub_responses(:describe_table, "ResourceNotFoundException")

      expect_raises(ArgumentError, "Unsupported billing mode FREE_LUNCH") { config.migrate! }
    end

    it "will raise a validation error if ppr is set with throughput" do
      config = Aws::Record::TableConfig.define do |table|
        table.model_class TestModel
        table.read_capacity_units 5
        table.write_capacity_units 3
        table.billing_mode "PAY_PER_REQUEST"
        table.client_options(**stub_options)
      end
      config.client.stub_responses(:describe_table, "ResourceNotFoundException")

      expect_raises(ArgumentError, "Cannot have billing mode PAY_PER_REQUEST with provisioned capacity.") do
        config.migrate!
      end
    end
  end
end

# Parity: 47/47 examples from spec/aws-record/record/table_config_spec.rb (aws-record 2.15.1)
