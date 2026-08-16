require "./base"
require "./errors"

# The update expression built from an item's changed attributes.
#
# The placeholder tokens are the same the Ruby gem produces — `#UE_A`, `#UE_B`, … and `:ue_a`,
# `:ue_b`, … — so an item written by either library reads the same.
struct Aws::Record::UpdateExpression
  # The `SET`/`REMOVE` expression, or `nil` when nothing changed.
  getter update_expression : String?

  # The name placeholders used by the expression, or `nil` when there are none.
  getter expression_attribute_names : Hash(String, String)?

  # The value placeholders used by the expression, or `nil` when there are none.
  getter expression_attribute_values : Aws::DynamoDB::Item?

  # Creates an update expression.
  def initialize(@update_expression : String?, @expression_attribute_names : Hash(String, String)?,
                 @expression_attribute_values : Aws::DynamoDB::Item?) : Nil
  end

  # Folds this expression into *input*, with the caller's pass-through options winning per key.
  #
  # Works for any shape that has the three expression fields: `UpdateItemInput` and the transactional
  # `Update` both do.
  #
  # Raises `Aws::Record::Errors::UpdateExpressionCollision` when *input* brought an update expression
  # of its own, which cannot be combined with one generated from attribute changes.
  def apply_to(input : T) : T forall T
    if input.update_expression && @update_expression
      raise Aws::Record::Errors::UpdateExpressionCollision.new(
        "Using pass-through update expression with attribute updates is not supported."
      )
    end
    input.merge(
      update_expression: input.update_expression || @update_expression,
      expression_attribute_names: merge_names(input.expression_attribute_names),
      expression_attribute_values: merge_values(input.expression_attribute_values)
    )
  end

  private def merge_names(given : Hash(String, String)?) : Hash(String, String)?
    generated = @expression_attribute_names
    return given unless generated
    return generated unless given
    generated.merge(given)
  end

  private def merge_values(given : Aws::DynamoDB::Item?) : Aws::DynamoDB::Item?
    generated = @expression_attribute_values
    return given unless generated
    return generated unless given
    generated.merge(given)
  end
end

# Reads and writes of single items.
#
# The Ruby gem's `ItemOperations` module; here these are methods of `Aws::Record::Base`.
class Aws::Record::Base
  # Saves this item, raising `Errors::ValidationError` when `#valid?` says no.
  #
  # See `#save` for how the write is chosen.
  def save!(force : Bool = false, **opts) : Bool
    raise Errors::ValidationError.new("Validation hook returned false!") unless save(**{force: force}.merge(opts))
    true
  end

  # Saves this item, returning `false` when `#valid?` says no.
  #
  # An item whose key attributes have changed is treated as new and written with a conditional
  # `put_item` that will not clobber an existing item, raising `Errors::ConditionalWriteFailed` if
  # one is there; otherwise only the changed attributes are written with `update_item`. With
  # *force*, the item is simply put, overwriting whatever is in the table.
  #
  # Any other keyword argument is passed through to the underlying client call.
  def save(force : Bool = false, **opts : **T) : Bool forall T
    # Which operation runs is only known at run time, so `#save` cannot simply build one input shape;
    # an option neither `put_item` nor `update_item` has is rejected here instead.
    {%
      put_fields = Aws::DynamoDB::Types::PutItemInput.resolve.constant(:FIELD_NAMES)
      update_fields = Aws::DynamoDB::Types::UpdateItemInput.resolve.constant(:FIELD_NAMES)
      T.keys.each do |key|
        unless put_fields.includes?(key.stringify) || update_fields.includes?(key.stringify)
          raise "Unknown option #{key} for #save; put_item and update_item have no such parameter"
        end
      end
    %}
    saved = valid? ? perform_save(force, **opts) : false
    clean!
    saved
  end

  # Assigns *attrs* and saves, returning `false` when `#valid?` says no.
  def update(**attrs) : Bool
    assign_attributes(**attrs)
    save
  end

  # Assigns *attrs* and saves, raising `Errors::ValidationError` when `#valid?` says no.
  def update!(**attrs) : Bool
    assign_attributes(**attrs)
    save!
  end

  # Deletes the item with this item's key.
  def delete!(**opts) : Bool
    input = Aws::DynamoDB::Types::DeleteItemInput.new(**opts).merge(
      table_name: self.class.table_name, key: key_values
    )
    dynamodb_client.delete_item(input)
    @data.destroyed = true
  end

  # This item's key, serialized and keyed by storage name, as the client operations need it.
  #
  # Raises `Errors::KeyMissing` when a key attribute has no value.
  def key_values : Aws::DynamoDB::Item
    validate_key_values
    attributes = self.class.attributes
    item = Aws::DynamoDB::Item.new
    self.class.keys.each_value do |name|
      attribute = attributes.attribute_for(name)
      next unless attribute
      item[attribute.database_name] = attribute.serialize(@data.raw_value(name))
    end
    item
  end

  # The item to write, as `batch_write_item` and the transactional writes need it.
  def save_values : Aws::DynamoDB::Item
    build_item_for_save
  end

  # Reloads this item from DynamoDB, discarding any unsaved changes.
  #
  # Raises `Errors::NotFound` when the item is no longer there.
  def reload! : self
    key = Hash(String, Aws::Record::RawValue).new
    self.class.keys.each_value { |name| key[name] = @data.get_attribute(name) }
    record = self.class.find_with_opts(key: key)
    raise Errors::NotFound.new("No record found") unless record
    @data = record._data
    clean!
    self
  end

  # This item's data. Used by the record layer; not part of the public API.
  # :nodoc:
  def _data : Aws::Record::ItemData
    @data
  end

  # :nodoc:
  def build_item_for_save : Aws::DynamoDB::Item
    validate_key_values
    @data.populate_default_values
    @data.build_save_hash
  end

  # :nodoc:
  protected def validate_key_values : Nil
    missing = missing_key_values
    raise Errors::KeyMissing.new("Missing required keys: #{missing.join(", ")}") unless missing.empty?
  end

  # :nodoc:
  protected def missing_key_values : Array(String)
    self.class.keys.each_value.select { |name| @data.raw_value(name).nil? }.to_a
  end

  # :nodoc:
  #
  # Whether this item should be written as new: its key attributes have changed.
  def expect_new_item? : Bool
    self.class.keys.each_value.any? { |name| @data.attribute_dirty?(name) }
  end

  # :nodoc:
  #
  # The condition that keeps a "safe put" from clobbering an existing item.
  def prevent_overwrite_expression : Tuple(String, Hash(String, String))
    keys = self.class.key_attributes
    conditions = ["attribute_not_exists(#H)"]
    names = {} of String => String
    keys.hash_key_attribute.try { |attribute| names["#H"] = attribute.database_name }
    keys.range_key_attribute.try do |attribute|
      conditions << "attribute_not_exists(#R)"
      names["#R"] = attribute.database_name
    end
    {conditions.join(" and "), names}
  end

  # :nodoc:
  def dirty_changes_for_update : Hash(String, Aws::Record::RawValue)
    changes = Hash(String, Aws::Record::RawValue).new
    dirty.each { |name| changes[name] = @data.raw_value(name) }
    changes
  end

  # :nodoc:
  #
  # Backs the generated `increment_<name>!` of an `atomic_counter`. Unlike the Ruby gem it
  # substitutes the attribute's *storage* name, so a counter with a `database_attribute_name` works.
  protected def increment_counter!(name : String, increment : Int) : Int64
    if dirty?
      raise Errors::RecordError.new("Attributes need to be saved before atomic counter can be incremented")
    end
    response = dynamodb_client.update_item(
      table_name: self.class.table_name,
      key: key_values,
      expression_attribute_names: {"#n" => self.class.attributes.storage_name_for(name)},
      expression_attribute_values: Aws::DynamoDB::Item{":i" => increment.to_i64},
      update_expression: "SET #n = #n + :i",
      return_values: "UPDATED_NEW"
    )
    response.attributes.try { |attributes| assign_attributes(attributes) }
    @data.clean!
    Aws::Record::Marshalers::IntegerMarshaler.narrow(@data.get_attribute(name)) || 0_i64
  end

  private def perform_save(force : Bool, **opts) : Bool
    if force
      dynamodb_client.put_item(
        Aws::DynamoDB::Types::PutItemInput.from_options(**opts).merge(
          table_name: self.class.table_name, item: build_item_for_save
        )
      )
    elsif expect_new_item?
      safe_put(**opts)
    else
      perform_update(**opts)
    end
    @data.destroyed = false
    @data.new_record = false
    true
  end

  private def safe_put(**opts) : Nil
    condition, names = prevent_overwrite_expression
    input = Aws::DynamoDB::Types::PutItemInput.from_options(**opts).merge(
      table_name: self.class.table_name,
      item: build_item_for_save,
      condition_expression: condition,
      expression_attribute_names: names
    )
    dynamodb_client.put_item(input)
  rescue error : Aws::DynamoDB::Errors::ConditionalCheckFailedException
    raise Errors::ConditionalWriteFailed.new(
      "Conditional #put_item call failed! Check that conditional write " \
      "conditions are met, or include the :force option to clobber " \
      "the remote item.",
      error
    )
  end

  private def perform_update(**opts) : Nil
    expression = self.class.build_update_expression(dirty_changes_for_update)
    input = self.class.merge_update_expression(Aws::DynamoDB::Types::UpdateItemInput.from_options(**opts), expression)
    response = dynamodb_client.update_item(
      input.merge(table_name: self.class.table_name, key: key_values)
    )
    response.attributes.try { |attributes| assign_attributes(attributes) }
  end

  # Finds the item with the given key attributes, or `nil`.
  #
  # ```
  # MyModel.find(id: 1, name: "First")
  # ```
  #
  # Raises `Errors::KeyMissing` when a key attribute is not given.
  def self.find(**keys) : self?
    find_with_opts(key: keys)
  end

  # Finds the item with the given key, passing every other option through to `get_item`.
  #
  # ```
  # MyModel.find_with_opts(key: {id: 1, name: "First"}, consistent_read: true)
  # ```
  def self.find_with_opts(key : NamedTuple, **opts) : self?
    find_with_opts(**{key: raw_value_hash(key)}.merge(opts))
  end

  # :ditto:
  def self.find_with_opts(key : Hash(String, Aws::Record::RawValue), **opts) : self?
    input = Aws::DynamoDB::Types::GetItemInput.new(
      table_name: table_name, key: serialize_key(key)
    ).merge(**opts)
    item = dynamodb_client.get_item(input).item
    item ? build_item_from_resp(item) : nil
  end

  # Updates the item with the given key attributes, without reading it first.
  #
  # ```
  # MyModel.update(id: 1, name: "First", body: "Hello!")
  # ```
  #
  # Raises `Errors::KeyMissing` when a key attribute is not given.
  def self.update(**attrs) : Nil
    update(attrs)
  end

  # :ditto:
  #
  # This form takes the pass-through options separately, as the Ruby gem's second argument does.
  def self.update(attrs : NamedTuple, **opts) : Nil
    values = raw_value_hash(attrs)
    key = Aws::DynamoDB::Item.new
    keys.each_value do |name|
      raw = values.delete(name)
      raise Errors::KeyMissing.new("Missing required key #{name} in #{attrs}") if raw.nil?
      attribute = attributes.attribute_for(name)
      key[attribute.database_name] = attribute.serialize(raw) if attribute
    end
    expression = build_update_expression(values)
    input = merge_update_expression(Aws::DynamoDB::Types::UpdateItemInput.new(**opts), expression)
    dynamodb_client.update_item(input.merge(table_name: table_name, key: key))
  end

  # Reads several items of this model in one `BatchGetItem`.
  #
  # ```
  # MyModel.find_all([{"id" => 1_i64, "name" => "n1"}, {"id" => 2_i64, "name" => "n2"}])
  # ```
  def self.find_all(keys : Array(Hash(String, Aws::Record::RawValue))) : Aws::Record::BatchRead
    model = self
    Aws::Record::Batch.read(client: dynamodb_client) do |batch|
      keys.each { |key| batch.find(model, key) }
    end
  end

  # Builds one item of a transactional read of this model.
  #
  # See `Aws::Record::Transactions.transact_find`.
  def self.tfind_opts(key : NamedTuple, **opts) : Aws::Record::TransactGetItemRequest
    tfind_opts(**{key: raw_value_hash(key)}.merge(opts))
  end

  # :ditto:
  def self.tfind_opts(key : Hash(String, Aws::Record::RawValue), **opts) : Aws::Record::TransactGetItemRequest
    Aws::Record::TransactGetItemRequest.new(
      self, Aws::DynamoDB::Types::Get.new(**opts).merge(table_name: table_name, key: serialize_key(key))
    )
  end

  # Reads several items of this model in one transaction.
  #
  # ```
  # MyModel.transact_find([{"hk" => "hk1", "rk" => "rk1"}, {"hk" => "hk2", "rk" => "rk2"}])
  # ```
  def self.transact_find(transact_items : Array(Hash(String, Aws::Record::RawValue)),
                         **opts) : Aws::Record::TransactFindResult
    requests = transact_items.map { |key| tfind_opts(key) }
    Aws::Record::Transactions.transact_find(**{transact_items: requests, client: dynamodb_client}.merge(opts))
  end

  # Builds a check to run as part of a transactional write, with this model's table and key.
  #
  # ```
  # check = MyModel.transact_check_expression(
  #   key: {uuid: "foo"},
  #   condition_expression: "size(#T) <= :v",
  #   expression_attribute_names: {"#T" => "body"},
  #   expression_attribute_values: Aws::DynamoDB::Item{":v" => 1024_i64}
  # )
  # ```
  def self.transact_check_expression(key : NamedTuple, **opts) : Aws::DynamoDB::Types::ConditionCheck
    Aws::DynamoDB::Types::ConditionCheck.new(**opts).merge(
      table_name: table_name, key: serialize_key(raw_value_hash(key))
    )
  end

  # Builds an item of this model from a DynamoDB item, marked as already persisted.
  def self.build_item_from_resp(item : Aws::DynamoDB::Item) : self
    record = new
    data = record._data
    attributes.attributes.each do |name, attribute|
      data.set_attribute(name, attribute.extract(item))
    end
    data.new_record = false
    record.clean!
    record
  end

  # The update expression that writes *pairs*, with the Ruby gem's placeholder tokens.
  def self.build_update_expression(pairs : Hash(String, Aws::Record::RawValue)) : Aws::Record::UpdateExpression
    set_expressions = [] of String
    remove_expressions = [] of String
    names = {} of String => String
    values = Aws::DynamoDB::Item.new
    name_token = "UE_A"
    value_token = "ue_a"
    pairs.each do |name, value|
      attribute = attributes.attribute_for(name)
      next unless attribute
      name_sub = "##{name_token}"
      value_sub = ":#{value_token}"
      name_token = name_token.succ
      value_token = value_token.succ
      names[name_sub] = attribute.database_name
      if value.nil? && !attribute.persist_nil?
        remove_expressions << name_sub
      else
        set_expressions << "#{name_sub} = #{value_sub}"
        values[value_sub] = attribute.serialize(value)
      end
    end
    expressions = [] of String
    expressions << "SET #{set_expressions.join(", ")}" unless set_expressions.empty?
    expressions << "REMOVE #{remove_expressions.join(", ")}" unless remove_expressions.empty?
    Aws::Record::UpdateExpression.new(
      expressions.empty? ? nil : expressions.join(" "),
      names.empty? ? nil : names,
      values.empty? ? nil : values
    )
  end

  # Folds *expression* into *input*, with the caller's pass-through options winning per key.
  #
  # Raises `Errors::UpdateExpressionCollision` when the caller brought an update expression of their
  # own, which cannot be combined with the one generated from attribute changes.
  def self.merge_update_expression(input : Aws::DynamoDB::Types::UpdateItemInput,
                                   expression : Aws::Record::UpdateExpression) : Aws::DynamoDB::Types::UpdateItemInput
    expression.apply_to(input)
  end

  # :nodoc:
  #
  # Converts a named tuple of attribute values into the string keyed hash the record layer uses.
  def self.raw_value_hash(values : NamedTuple) : Hash(String, Aws::Record::RawValue)
    hash = Hash(String, Aws::Record::RawValue).new
    values.each { |name, value| hash[name.to_s] = Aws::Record::RawValues.from(value) }
    hash
  end

  private def self.serialize_key(key : Hash(String, Aws::Record::RawValue)) : Aws::DynamoDB::Item
    request_key = Aws::DynamoDB::Item.new
    keys.each_value do |name|
      raise Errors::KeyMissing.new("Missing required key #{name} in #{key}") if key[name]?.nil?
      attribute = attributes.attribute_for(name)
      request_key[attribute.database_name] = attribute.serialize(key[name]) if attribute
    end
    request_key
  end
end
