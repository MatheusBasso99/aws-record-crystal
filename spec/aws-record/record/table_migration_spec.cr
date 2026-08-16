require "../../spec_helper"

module TableMigrationSpec
  class NoKeyModel < Aws::Record::Base
  end

  class ClientModel < Aws::Record::Base
    set_table_name "TestTable"
    integer_attr :id, hash_key: true
  end

  class TestModel < Aws::Record::Base
    set_table_name "TestTable"
    integer_attr :id, hash_key: true
    date_attr :date, range_key: true, database_attribute_name: "datekey"
    string_attr :lsi
    string_attr :gsi_partition
    string_attr :gsi_sort
  end

  class LsiModel < Aws::Record::Base
    set_table_name "TestTable"
    integer_attr :id, hash_key: true
    date_attr :date, range_key: true, database_attribute_name: "datekey"
    string_attr :lsi

    local_secondary_index :test_lsi, range_key: :lsi, projection: {projection_type: "ALL"}
  end

  class GsiModel < Aws::Record::Base
    set_table_name "TestTable"
    integer_attr :id, hash_key: true
    date_attr :date, range_key: true, database_attribute_name: "datekey"
    string_attr :gsi_partition
    string_attr :gsi_sort

    global_secondary_index :test_gsi, hash_key: :gsi_partition, range_key: :gsi_sort,
      projection: {projection_type: "ALL"}
  end

  class TwoGsiModel < Aws::Record::Base
    set_table_name "TestTable"
    integer_attr :id, hash_key: true
    date_attr :date, range_key: true, database_attribute_name: "datekey"
    string_attr :gsi_partition
    string_attr :gsi_sort

    global_secondary_index :test_gsi, hash_key: :gsi_partition, range_key: :gsi_sort,
      projection: {projection_type: "ALL"}
    global_secondary_index :fail_on, hash_key: :gsi_partition, range_key: :gsi_sort,
      projection: {projection_type: "ALL"}
  end
end

private def throughput(read : Int64 = 5, write : Int64 = 2) : Aws::DynamoDB::Types::ProvisionedThroughput
  Aws::DynamoDB::Types::ProvisionedThroughput.new(read_capacity_units: read, write_capacity_units: write)
end

private def base_create_json : String
  %("TableName":"TestTable","AttributeDefinitions":[) +
    %({"AttributeName":"id","AttributeType":"N"},{"AttributeName":"datekey","AttributeType":"S"}],) +
    %("KeySchema":[{"AttributeName":"id","KeyType":"HASH"},{"AttributeName":"datekey","KeyType":"RANGE"}])
end

describe Aws::Record::TableMigration do
  it "only accepts Aws::Record models" do
    expect_compile_error("migration_non_model.cr", "to be Aws::Record::Base.class")
  end

  it "requires that models contain a valid key" do
    expect_raises(Aws::Record::Errors::InvalidModel, "Table models must include a hash key") do
      Aws::Record::TableMigration.new(TableMigrationSpec::NoKeyModel)
    end
  end

  describe "client" do
    it "uses client given as option with the highest priority" do
      model_client = stub_client
      given_client = stub_client
      TableMigrationSpec::ClientModel.configure_client(client: model_client)

      Aws::Record::TableMigration.new(TableMigrationSpec::ClientModel, client: given_client)
        .client.should be(given_client)
    end

    it "uses client set to model" do
      model_client = stub_client
      TableMigrationSpec::ClientModel.configure_client(client: model_client)

      Aws::Record::TableMigration.new(TableMigrationSpec::ClientModel).client.should be(model_client)
    end
  end

  describe "Migration Operations" do
    describe "#create!" do
      it "calls #create_table on a client when #create! is called" do
        client = stub_client
        migration = Aws::Record::TableMigration.new(TableMigrationSpec::TestModel, client: client)
        migration.create!(provisioned_throughput: throughput)

        api_requests(client).map(&.params).should eq([
          JSON.parse(
            %({#{base_create_json},) +
            %("ProvisionedThroughput":{"ReadCapacityUnits":5,"WriteCapacityUnits":2}})
          ),
        ])
      end

      it "allows specifying on-demand billing instead of provisioned througput" do
        client = stub_client
        migration = Aws::Record::TableMigration.new(TableMigrationSpec::TestModel, client: client)
        migration.create!(billing_mode: "PAY_PER_REQUEST")

        api_requests(client).map(&.params).should eq([
          JSON.parse(%({#{base_create_json},"BillingMode":"PAY_PER_REQUEST"})),
        ])
      end

      it "accepts a value of PROVISIONED for billing_mode if provisioned throughput is also specified" do
        client = stub_client
        migration = Aws::Record::TableMigration.new(TableMigrationSpec::TestModel, client: client)
        migration.create!(billing_mode: "PROVISIONED", provisioned_throughput: throughput)

        api_requests(client).map(&.params).should eq([
          JSON.parse(
            %({#{base_create_json},"BillingMode":"PROVISIONED",) +
            %("ProvisionedThroughput":{"ReadCapacityUnits":5,"WriteCapacityUnits":2}})
          ),
        ])
      end

      it "requires billing_mode be PROVISIONED if specified and provisioned throughput is provided" do
        client = stub_client
        migration = Aws::Record::TableMigration.new(TableMigrationSpec::TestModel, client: client)

        expect_raises(ArgumentError, ":billing_mode option must be one of PAY_PER_REQUEST, PROVISIONED") do
          migration.create!(billing_mode: "INVALID", provisioned_throughput: throughput)
        end
        api_requests(client).should be_empty
      end

      it "requires billing_mode be PAY_PER_REQUEST if specified and no provisioned throughput is provided" do
        client = stub_client
        migration = Aws::Record::TableMigration.new(TableMigrationSpec::TestModel, client: client)

        expect_raises(ArgumentError, "current value is: INVALID") { migration.create!(billing_mode: "INVALID") }
        api_requests(client).should be_empty
      end

      it "requires billing_mode be specified and have value PAY_PER_REQUEST if no provisioned " \
         "throughput is provided" do
        client = stub_client
        migration = Aws::Record::TableMigration.new(TableMigrationSpec::TestModel, client: client)

        expect_raises(ArgumentError, "when :provisioned_throughput option is not specified") { migration.create! }
        api_requests(client).should be_empty
      end

      it "requires only one capacity specification, either provisioned throughput or on-demand" do
        client = stub_client
        migration = Aws::Record::TableMigration.new(TableMigrationSpec::TestModel, client: client)

        expect_raises(ArgumentError, "when :provisioned_throughput option is specified") do
          migration.create!(billing_mode: "PAY_PER_REQUEST", provisioned_throughput: throughput)
        end
        api_requests(client).should be_empty
      end

      it "accepts models with a local secondary index" do
        client = stub_client
        migration = Aws::Record::TableMigration.new(TableMigrationSpec::LsiModel, client: client)
        migration.create!(provisioned_throughput: throughput)

        api_requests(client).map(&.params).should eq([
          JSON.parse(
            %({"TableName":"TestTable","AttributeDefinitions":[) +
            %({"AttributeName":"id","AttributeType":"N"},{"AttributeName":"datekey","AttributeType":"S"},) +
            %({"AttributeName":"lsi","AttributeType":"S"}],) +
            %("KeySchema":[{"AttributeName":"id","KeyType":"HASH"},) +
            %({"AttributeName":"datekey","KeyType":"RANGE"}],) +
            %("LocalSecondaryIndexes":[{"IndexName":"test_lsi","KeySchema":[) +
            %({"AttributeName":"id","KeyType":"HASH"},{"AttributeName":"lsi","KeyType":"RANGE"}],) +
            %("Projection":{"ProjectionType":"ALL"}}],) +
            %("ProvisionedThroughput":{"ReadCapacityUnits":5,"WriteCapacityUnits":2}})
          ),
        ])
      end

      it "accepts models with a global secondary index" do
        client = stub_client
        migration = Aws::Record::TableMigration.new(TableMigrationSpec::GsiModel, client: client)
        migration.create!(
          provisioned_throughput: throughput,
          global_secondary_index_throughput: {"test_gsi" => throughput(3_i64, 1_i64)}
        )

        api_requests(client).map(&.params).should eq([
          JSON.parse(
            %({"TableName":"TestTable","AttributeDefinitions":[) +
            %({"AttributeName":"id","AttributeType":"N"},{"AttributeName":"datekey","AttributeType":"S"},) +
            %({"AttributeName":"gsi_partition","AttributeType":"S"},) +
            %({"AttributeName":"gsi_sort","AttributeType":"S"}],) +
            %("KeySchema":[{"AttributeName":"id","KeyType":"HASH"},) +
            %({"AttributeName":"datekey","KeyType":"RANGE"}],) +
            %("GlobalSecondaryIndexes":[{"IndexName":"test_gsi","KeySchema":[) +
            %({"AttributeName":"gsi_partition","KeyType":"HASH"},) +
            %({"AttributeName":"gsi_sort","KeyType":"RANGE"}],) +
            %("Projection":{"ProjectionType":"ALL"},) +
            %("ProvisionedThroughput":{"ReadCapacityUnits":3,"WriteCapacityUnits":1}}],) +
            %("ProvisionedThroughput":{"ReadCapacityUnits":5,"WriteCapacityUnits":2}})
          ),
        ])
      end

      it "does not require global secondary index throughput to be provided if the table is " \
         "configured to use on-demand billing" do
        client = stub_client
        migration = Aws::Record::TableMigration.new(TableMigrationSpec::GsiModel, client: client)
        migration.create!(billing_mode: "PAY_PER_REQUEST")

        api_requests(client)[0].params["GlobalSecondaryIndexes"][0]["ProvisionedThroughput"]?.should be_nil
        api_requests(client)[0].params["BillingMode"].should eq("PAY_PER_REQUEST")
      end

      describe "when the table is not configured to use on-demand billing" do
        it "requires global secondary index throughput to be provided" do
          client = stub_client
          migration = Aws::Record::TableMigration.new(TableMigrationSpec::GsiModel, client: client)

          expect_raises(ArgumentError, ":global_secondary_index_throughput") do
            migration.create!(provisioned_throughput: throughput)
          end
          api_requests(client).should be_empty
        end

        it "requires global secondary index throughput to be defined for each index" do
          client = stub_client
          migration = Aws::Record::TableMigration.new(TableMigrationSpec::TwoGsiModel, client: client)

          expect_raises(ArgumentError, "fail_on") do
            migration.create!(
              provisioned_throughput: throughput,
              global_secondary_index_throughput: {"test_gsi" => throughput(1_i64, 1_i64)}
            )
          end
          api_requests(client).should be_empty
        end
      end
    end

    describe "#delete!" do
      it "calls #delete_table on a client when #delete! is called" do
        client = stub_client
        migration = Aws::Record::TableMigration.new(TableMigrationSpec::TestModel, client: client)
        migration.delete!

        api_requests(client).map(&.params).should eq([JSON.parse(%({"TableName":"TestTable"}))])
      end

      it "throws TableDoesNotExist when table did not exist at call time" do
        client = stub_client
        client.stub_responses(:delete_table, "ResourceNotFoundException")
        migration = Aws::Record::TableMigration.new(TableMigrationSpec::TestModel, client: client)

        expect_raises(Aws::Record::Errors::TableDoesNotExist) { migration.delete! }
      end
    end

    describe "#update!" do
      it "calles #update_table on a client when #update! is called" do
        client = stub_client
        migration = Aws::Record::TableMigration.new(TableMigrationSpec::TestModel, client: client)
        migration.update!(provisioned_throughput: throughput(4_i64, 3_i64))

        api_requests(client).map(&.params).should eq([
          JSON.parse(
            %({"TableName":"TestTable",) +
            %("ProvisionedThroughput":{"ReadCapacityUnits":4,"WriteCapacityUnits":3}})
          ),
        ])
      end

      it "throws TableDoesNotExist when table did not exist at call time" do
        client = stub_client
        client.stub_responses(:update_table, "ResourceNotFoundException")
        migration = Aws::Record::TableMigration.new(TableMigrationSpec::TestModel, client: client)

        expect_raises(Aws::Record::Errors::TableDoesNotExist) { migration.update! }
      end
    end

    describe "#wait_until_available" do
      it "can check on the table's availability status" do
        client = stub_client
        client.stub_responses(
          :describe_table,
          Aws::DynamoDB::Types::DescribeTableOutput.new(
            table: Aws::DynamoDB::Types::TableDescription.new(table_status: "ACTIVE")
          )
        )
        migration = Aws::Record::TableMigration.new(TableMigrationSpec::TestModel, client: client)

        migration.wait_until_available.table_status.should eq("ACTIVE")
      end
    end
  end
end

# Parity: 21/21 examples from spec/aws-record/record/table_migration_spec.rb (aws-record 2.15.1)
