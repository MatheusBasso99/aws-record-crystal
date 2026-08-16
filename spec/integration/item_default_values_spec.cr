require "../spec_helper"

module IntegrationSpec
  class DefaultValuesModel < Aws::Record::Base
    string_attr :uuid, hash_key: true
    map_attr :map, default_value: Aws::DynamoDB::Item.new
  end
end

# Ported from features/items/item_default_values.feature.
describe "Amazon DynamoDB Item Default Values", tags: "integration" do
  it "Write From Default Values" do
    integration!
    with_model_table(IntegrationSpec::DefaultValuesModel) do
      first = IntegrationSpec::DefaultValuesModel.new(uuid: "1")
      first.map.try { |map| map["a"] = 1_i64 }
      first.save!

      second = IntegrationSpec::DefaultValuesModel.new(uuid: "2")
      second.map.try { |map| map["b"] = 2_i64 }
      second.save!

      IntegrationSpec::DefaultValuesModel
        .find_with_opts(key: {uuid: "1"}, consistent_read: true).try(&.map)
        .should eq(Aws::DynamoDB::Item{"a" => 1_i64})
      IntegrationSpec::DefaultValuesModel
        .find_with_opts(key: {uuid: "2"}, consistent_read: true).try(&.map)
        .should eq(Aws::DynamoDB::Item{"b" => 2_i64})
    end
  end
end

# Parity: 1/1 scenario from features/items/item_default_values.feature (aws-record 2.15.1)
