require "./base"
require "./errors"

# A batch of reads to run with `BatchGetItem` calls.
#
# Built by `Aws::Record::Batch.read`; the reads it collects may span tables and models, and each item
# comes back as the model it was asked for. DynamoDB reads at most 100 keys per call, so a larger
# batch is split, and whatever it could not process is kept for a further `#execute!` — which
# iterating does for you.
class Aws::Record::BatchRead
  include Enumerable(Aws::Record::Base)

  # The most keys DynamoDB reads in one `BatchGetItem` call.
  BATCH_GET_ITEM_LIMIT = 100

  # One key still to read, and the table to read it from.
  # :nodoc:
  struct PendingKey
    # The serialized key.
    getter keys : Aws::DynamoDB::Item

    # The table the key belongs to.
    getter table_name : String

    # Creates a pending key.
    def initialize(@keys : Aws::DynamoDB::Item, @table_name : String) : Nil
    end
  end

  # A key that was asked for, and the model it should come back as.
  # :nodoc:
  struct ExpectedItem
    # The serialized key.
    getter keys : Aws::DynamoDB::Item

    # The model the item is built into.
    getter model_class : Aws::Record::Base.class

    # Creates an expectation.
    def initialize(@keys : Aws::DynamoDB::Item, @model_class : Aws::Record::Base.class) : Nil
    end
  end

  # The items read so far.
  getter items : Array(Aws::Record::Base)

  # Creates an empty batch that reads through *client*.
  def initialize(@client : Aws::DynamoDB::Client) : Nil
    @items = [] of Aws::Record::Base
    @pending = [] of PendingKey
    @expected = Hash(String, Array(ExpectedItem)).new { |hash, key| hash[key] = [] of ExpectedItem }
  end

  # Adds the item of *model* with the given key attributes to the batch.
  #
  # Raises `Errors::KeyMissing` when a key attribute is not given, and `ArgumentError` when the same
  # key was already asked for as a different model.
  def find(model : Aws::Record::Base.class, **key) : Nil
    find(model, Aws::Record::Base.raw_value_hash(key))
  end

  # :ditto:
  def find(model : Aws::Record::Base.class, key : Hash(String, Aws::Record::RawValue)) : Nil
    item_key = format_key(model, key)
    @pending << PendingKey.new(item_key, model.table_name)
    remember(model, item_key)
  end

  # Reads the next batch of up to 100 keys and returns the items it produced.
  def execute! : Array(Aws::Record::Base)
    keys = @pending[0, BATCH_GET_ITEM_LIMIT]
    @pending = @pending[BATCH_GET_ITEM_LIMIT..]? || [] of PendingKey
    response = @client.batch_get_item(request_items: request_items(keys))
    new_items = build_items(response.responses)
    @items.concat(new_items)
    response.unprocessed_keys.try { |unprocessed| queue_unprocessed(unprocessed) }
    new_items
  end

  # Yields every item, reading further batches until there are no keys left.
  def each(& : Aws::Record::Base ->) : Nil
    @items.each { |item| yield item }
    until complete?
      execute!.each { |item| yield item }
    end
  end

  # Whether every key asked for has been read.
  def complete? : Bool
    @pending.empty?
  end

  private def format_key(model, key) : Aws::DynamoDB::Item
    attributes = model.attributes
    item_key = Aws::DynamoDB::Item.new
    model.keys.each_value do |name|
      raise Errors::KeyMissing.new("Missing required key #{name} in #{key}") if key[name]?.nil?
      attribute = attributes.attribute_for(name)
      item_key[attribute.database_name] = attribute.serialize(key[name]) if attribute
    end
    item_key
  end

  private def remember(model, item_key) : Nil
    expectations = @expected[model.table_name]
    expectations.each do |expectation|
      if expectation.keys == item_key && expectation.model_class != model
        raise ArgumentError.new("Provided item keys is a duplicate request")
      end
    end
    expectations << ExpectedItem.new(item_key, model)
  end

  private def request_items(keys) : Hash(String, Aws::DynamoDB::Types::KeysAndAttributes)
    grouped = Hash(String, Array(Aws::DynamoDB::Item)).new { |hash, key| hash[key] = [] of Aws::DynamoDB::Item }
    keys.each { |pending| grouped[pending.table_name] << pending.keys }
    request = {} of String => Aws::DynamoDB::Types::KeysAndAttributes
    grouped.each { |table, items| request[table] = Aws::DynamoDB::Types::KeysAndAttributes.new(keys: items) }
    request
  end

  private def build_items(responses) : Array(Aws::Record::Base)
    new_items = [] of Aws::Record::Base
    return new_items unless responses
    responses.each do |table, items|
      items.each do |item|
        model = model_for(table, item)
        if model
          new_items << model.build_item_from_resp(item)
        else
          Aws::Record::Log.warn do
            "Unexpected response from service.Received: #{item}. Skipping above item and continuing"
          end
        end
      end
    end
    new_items
  end

  private def model_for(table, item) : (Aws::Record::Base.class)?
    @expected[table]?.try do |expectations|
      expectations.find { |expectation| contains_keys?(item, expectation.keys) }.try(&.model_class)
    end
  end

  private def contains_keys?(item, keys) : Bool
    keys.all? { |name, value| item[name]? == value }
  end

  private def queue_unprocessed(unprocessed) : Nil
    unprocessed.each do |table, keys_and_attributes|
      keys_and_attributes.keys.try(&.each { |key| @pending << PendingKey.new(key, table) })
    end
  end
end
