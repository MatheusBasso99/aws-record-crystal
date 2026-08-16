require "./base"
require "./buildable_search"
require "./item_collection"

# Searching a model's table.
#
# The Ruby gem's `Query` module; here these are class methods of `Aws::Record::Base`.
class Aws::Record::Base
  # Runs a query and returns its lazy result.
  #
  # ```
  # Forum.query(
  #   key_condition_expression: "#H = :h",
  #   expression_attribute_names: {"#H" => "forum_uuid"},
  #   expression_attribute_values: Aws::DynamoDB::Item{":h" => "uuid"}
  # )
  # ```
  def self.query(input : Aws::DynamoDB::Types::QueryInput,
                 model_filter : Proc(Aws::DynamoDB::Item, (Aws::Record::Base.class)?)? = nil) : ItemCollection
    pages = dynamodb_client.query_pages(input.merge(table_name: table_name))
    ItemCollection.new(TypedSearchPages.new(pages), self, model_filter)
  end

  # :ditto:
  def self.query(**opts) : ItemCollection
    query(Aws::DynamoDB::Types::QueryInput.new(**opts))
  end

  # Runs a scan and returns its lazy result.
  def self.scan(input : Aws::DynamoDB::Types::ScanInput,
                model_filter : Proc(Aws::DynamoDB::Item, (Aws::Record::Base.class)?)? = nil) : ItemCollection
    pages = dynamodb_client.scan_pages(input.merge(table_name: table_name))
    ItemCollection.new(TypedSearchPages.new(pages), self, model_filter)
  end

  # :ditto:
  def self.scan(**opts) : ItemCollection
    scan(Aws::DynamoDB::Types::ScanInput.new(**opts))
  end

  # Starts building a query; see `BuildableSearch`.
  def self.build_query : BuildableSearch
    BuildableSearch.new(:query, self)
  end

  # Starts building a scan; see `BuildableSearch`.
  def self.build_scan : BuildableSearch
    BuildableSearch.new(:scan, self)
  end
end
