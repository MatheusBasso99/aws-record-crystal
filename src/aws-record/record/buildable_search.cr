require "./errors"
require "./item_collection"

# Builds a query or a scan a step at a time, substituting attribute names and values for you.
#
# `:name` in an expression is replaced by the storage name of that attribute under a `#BUILDERA`
# style placeholder, and every `?` by the next value under a `:buildera` style one — the same tokens
# the Ruby gem produces.
#
# ```
# Forum.build_query
#   .key_expr(":forum_uuid = ? AND begins_with(:post_title, ?)", "uuid", "prefix")
#   .scan_ascending(false)
#   .limit(10)
#   .complete!
# ```
class Aws::Record::BuildableSearch
  # The operations this can build.
  SUPPORTED_OPERATIONS = [:query, :scan]

  @index_name : String?
  @consistent_read : Bool?
  @scan_index_forward : Bool?
  @total_segments : Int32?
  @segment : Int32?
  @limit : Int32?
  @exclusive_start_key : Aws::DynamoDB::Item?
  @key_condition_expression : String?
  @filter_expression : String?
  @projection_expression : String?
  @model_filter : Proc(Aws::DynamoDB::Item, (Aws::Record::Base.class)?)?
  @names = {} of String => String
  @values = Aws::DynamoDB::Item.new
  @next_name = "BUILDERA"
  @next_value = "buildera"

  # Creates a builder for *operation* over *model*.
  #
  # Raises `ArgumentError` for an operation other than `:query` or `:scan`.
  def initialize(@operation : Symbol, @model : Aws::Record::Base.class) : Nil
    raise ArgumentError.new("Unsupported operation: #{@operation}") unless SUPPORTED_OPERATIONS.includes?(@operation)
  end

  # Runs the search against the named secondary index.
  def on_index(index : String | Symbol) : self
    @index_name = index.to_s
    self
  end

  # Asks for a strongly consistent read.
  def consistent_read(value : Bool) : self
    @consistent_read = value
    self
  end

  # Splits a scan into *total_segments* parts and reads part *segment*.
  #
  # Raises `ArgumentError` for a query, which cannot be segmented.
  def parallel_scan(total_segments : Int32, segment : Int32) : self
    raise ArgumentError.new("parallel_scan is only supported for scans") unless @operation == :scan
    @total_segments = total_segments
    @segment = segment
    self
  end

  # Reads a query's range key in ascending (`true`) or descending (`false`) order.
  #
  # Raises `ArgumentError` for a scan, which has no order to choose.
  def scan_ascending(value : Bool) : self
    raise ArgumentError.new("scan_ascending is only supported for queries.") unless @operation == :query
    @scan_index_forward = value
    self
  end

  # Starts reading after the given pagination key.
  def exclusive_start_key(key : Aws::DynamoDB::Item) : self
    @exclusive_start_key = key
    self
  end

  # :ditto:
  def exclusive_start_key(key : NamedTuple) : self
    item = Aws::DynamoDB::Item.new
    key.each { |name, value| item[name.to_s] = Aws::DynamoDB::Values.from(value) }
    exclusive_start_key(item)
  end

  # Sets a query's key condition, substituting `:attribute` names and `?` values.
  #
  # Raises `ArgumentError` for a scan, which has no key condition.
  def key_expr(statement : String, *subs : _) : self
    raise ArgumentError.new("key_expr is only supported for queries.") unless @operation == :query
    @key_condition_expression = substitute(statement, subs)
    self
  end

  # Sets the filter expression, substituting `:attribute` names and `?` values.
  def filter_expr(statement : String, *subs : _) : self
    @filter_expression = substitute(statement, subs)
    self
  end

  # Sets the projection expression, substituting `:attribute` names.
  def projection_expr(statement : String) : self
    @projection_expression = substitute_names(statement)
    self
  end

  # Reads at most *size* items per page.
  def limit(size : Int32) : self
    @limit = size
    self
  end

  # Chooses the model class of each item from its raw attributes; returning `nil` skips the item.
  def multi_model_filter(&block : Aws::DynamoDB::Item -> (Aws::Record::Base.class)?) : self
    @model_filter = block
    self
  end

  # Runs the search and returns its lazy result.
  def complete! : ItemCollection
    if @operation == :query
      @model.query(query_input, model_filter: @model_filter)
    else
      @model.scan(scan_input, model_filter: @model_filter)
    end
  end

  private def query_input : Aws::DynamoDB::Types::QueryInput
    Aws::DynamoDB::Types::QueryInput.new(
      index_name: @index_name,
      limit: @limit,
      consistent_read: @consistent_read,
      scan_index_forward: @scan_index_forward,
      exclusive_start_key: @exclusive_start_key,
      projection_expression: @projection_expression,
      filter_expression: @filter_expression,
      key_condition_expression: @key_condition_expression,
      expression_attribute_names: @names.empty? ? nil : @names,
      expression_attribute_values: @values.empty? ? nil : @values
    )
  end

  private def scan_input : Aws::DynamoDB::Types::ScanInput
    Aws::DynamoDB::Types::ScanInput.new(
      index_name: @index_name,
      limit: @limit,
      consistent_read: @consistent_read,
      exclusive_start_key: @exclusive_start_key,
      total_segments: @total_segments,
      segment: @segment,
      projection_expression: @projection_expression,
      filter_expression: @filter_expression,
      expression_attribute_names: @names.empty? ? nil : @names,
      expression_attribute_values: @values.empty? ? nil : @values
    )
  end

  private def substitute(statement : String, subs) : String
    apply_values(substitute_names(statement), subs)
  end

  private def substitute_names(statement : String) : String
    statement.gsub(/:(\w+)/) do |_match, match|
      key = match[1]
      storage_name = @model.attributes.attribute_for(key).try(&.database_name)
      raise ArgumentError.new("No such key #{key}") unless storage_name
      placeholder = next_name
      raise Errors::RecordError.new("Substitution collision!") if @names[placeholder]?
      @names[placeholder] = storage_name
      placeholder
    end
  end

  private def apply_values(statement : String, subs) : String
    count = 0
    result = statement.gsub(/[?]/) do
      placeholder = next_value
      raise Errors::RecordError.new("Substitution collision!") if @values[placeholder]?
      @values[placeholder] = value_at(subs, count)
      count += 1
      placeholder
    end
    unless count == subs.size
      raise ArgumentError.new("Expected #{count} values in the substitution set, but found #{subs.size}")
    end
    result
  end

  private def value_at(subs, index) : Aws::DynamoDB::Value
    position = 0
    subs.each do |sub|
      return Aws::DynamoDB::Values.from(sub) if position == index
      position += 1
    end
    raise ArgumentError.new("Expected #{index + 1} values in the substitution set, but found #{subs.size}")
  end

  private def next_name : String
    placeholder = "##{@next_name}"
    @next_name = @next_name.succ
    placeholder
  end

  private def next_value : String
    placeholder = ":#{@next_value}"
    @next_value = @next_value.succ
    placeholder
  end
end
