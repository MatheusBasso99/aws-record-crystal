require "../spec_helper"

module IntegrationSpec
  class SearchModel < Aws::Record::Base
    string_attr :id, hash_key: true
    integer_attr :count, range_key: true
    string_attr :body, database_attribute_name: "content"
  end

  # The heterogeneous query reads the same table as two different models.
  class SearchModelA < Aws::Record::Base
    string_attr :id, hash_key: true
    integer_attr :count, range_key: true
    string_attr :class_name
    string_attr :attr_a
  end

  class SearchModelB < Aws::Record::Base
    string_attr :id, hash_key: true
    integer_attr :count, range_key: true
    string_attr :class_name
    string_attr :attr_b
  end
end

private def with_search_table(& : Aws::DynamoDB::Client ->)
  with_model_table(IntegrationSpec::SearchModel) do |client|
    [
      {"1", 5_i64, "First item."},
      {"1", 10_i64, "Second item."},
      {"1", 15_i64, "Third item."},
      {"2", 10_i64, "Fourth item."},
    ].each do |id, count, body|
      client.put_item(
        table_name: IntegrationSpec::SearchModel.table_name,
        item: Aws::DynamoDB::Item{"id" => id, "count" => count, "content" => body}
      )
    end
    yield client
  end
end

private def bodies(collection : Aws::Record::ItemCollection) : Array(String?)
  collection.map { |record| record.as(IntegrationSpec::SearchModel).body }.to_a
end

# Ported from features/searching/search.feature.
describe "Amazon DynamoDB Searching", tags: "integration" do
  it "Run Query Directly From Aws::DynamoDB::Client#query" do
    integration!
    with_search_table do
      results = IntegrationSpec::SearchModel.query(
        key_conditions: {
          "id" => Aws::DynamoDB::Types::Condition.new(
            attribute_value_list: ["1"] of Aws::DynamoDB::Value, comparison_operator: "EQ"
          ),
          "count" => Aws::DynamoDB::Types::Condition.new(
            attribute_value_list: [7_i64] of Aws::DynamoDB::Value, comparison_operator: "GT"
          ),
        },
        consistent_read: true
      )
      bodies(results).should eq(["Second item.", "Third item."])
    end
  end

  it "Run Scan Directly From Aws::DynamoDB::Client#scan" do
    integration!
    with_search_table do
      bodies(IntegrationSpec::SearchModel.scan(consistent_read: true)).compact.sort!
        .should eq(["First item.", "Fourth item.", "Second item.", "Third item."])
    end
  end

  it "Paginate Manually With Multiple Calls" do
    integration!
    with_search_table do
      first = IntegrationSpec::SearchModel.scan(limit: 2, consistent_read: true)
      first.page.size.should eq(2)
      key = first.last_evaluated_key.should_not be_nil

      second = IntegrationSpec::SearchModel.scan(limit: 2, exclusive_start_key: key, consistent_read: true)
      second.page.size.should eq(2)

      seen = first.page.map { |record| record.as(IntegrationSpec::SearchModel).body } +
             second.page.map { |record| record.as(IntegrationSpec::SearchModel).body }
      seen.compact.sort!.should eq(["First item.", "Fourth item.", "Second item.", "Third item."])
    end
  end

  it "Heterogeneous query" do
    integration!
    client = DynamoDBLocal.client
    name = DynamoDBLocal.table_name("heterogeneous")
    [IntegrationSpec::SearchModelA, IntegrationSpec::SearchModelB].each do |model|
      model.configure_client(client: client)
      model.set_table_name(name)
    end
    migration = Aws::Record::TableMigration.new(IntegrationSpec::SearchModelA, client: client)
    begin
      migration.create!(provisioned_throughput: DynamoDBLocal.throughput)
      migration.wait_until_available
      IntegrationSpec::SearchModelA.new(id: "1", count: 1, class_name: "A", attr_a: "a").save!
      IntegrationSpec::SearchModelB.new(id: "1", count: 2, class_name: "B", attr_b: "b").save!

      results = IntegrationSpec::SearchModelA
        .build_query
        .key_expr(":id = ?", "1")
        .consistent_read(true)
        .multi_model_filter do |item|
          case item["class_name"]?
          when "A" then IntegrationSpec::SearchModelA.as(Aws::Record::Base.class)
          when "B" then IntegrationSpec::SearchModelB.as(Aws::Record::Base.class)
          end
        end
        .complete!

      classes = results.map(&.class).to_a
      classes.should eq([IntegrationSpec::SearchModelA, IntegrationSpec::SearchModelB])
    ensure
      delete_table(client, name)
    end
  end

  it "Build a Smart Scan" do
    integration!
    with_search_table do
      results = IntegrationSpec::SearchModel
        .build_scan.filter_expr(":body = ?", "Third item.").consistent_read(true).complete!
      bodies(results).should eq(["Third item."])
    end
  end

  it "Build a Smart Query" do
    integration!
    with_search_table do
      results = IntegrationSpec::SearchModel
        .build_query.key_expr(":id = ? AND :count > ?", "1", 7).consistent_read(true).complete!
      bodies(results).should eq(["Second item.", "Third item."])
    end
  end
end

# Parity: 6/6 scenarios from features/searching/search.feature (aws-record 2.15.1)
