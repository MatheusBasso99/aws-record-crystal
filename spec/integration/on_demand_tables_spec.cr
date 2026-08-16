require "../spec_helper"

module IntegrationSpec
  class OnDemandModel < Aws::Record::Base
    string_attr :id, hash_key: true
  end
end

# Ported from features/migrations/on_demand_tables.feature.
describe "Amazon DynamoDB On-Demand Tables", tags: "integration" do
  it "Create a DynamoDB Table with on-demand billing with aws-record" do
    integration!
    client = DynamoDBLocal.client
    IntegrationSpec::OnDemandModel.configure_client(client: client)
    IntegrationSpec::OnDemandModel.set_table_name(DynamoDBLocal.table_name("on_demand"))
    migration = Aws::Record::TableMigration.new(IntegrationSpec::OnDemandModel, client: client)
    begin
      migration.create!(billing_mode: "PAY_PER_REQUEST")
      migration.wait_until_available

      IntegrationSpec::OnDemandModel.table_exists?.should be_true
      IntegrationSpec::OnDemandModel.provisioned_throughput
        .should eq({read_capacity_units: 0_i64, write_capacity_units: 0_i64})
    ensure
      delete_table(client, IntegrationSpec::OnDemandModel.table_name)
    end
  end
end

# Parity: 1/1 scenario from features/migrations/on_demand_tables.feature (aws-record 2.15.1)
