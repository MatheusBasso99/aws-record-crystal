require "./model_attributes"
require "./raw_value"

# The attribute values of one item, plus everything dirty tracking needs to know what changed.
#
# Values are stored exactly as they were assigned and cast on read, which is what makes
# `Model.new(count: "5").count == 5` work the same way it does in Ruby.
class Aws::Record::ItemData
  # Whether this item has never been written to DynamoDB.
  property? new_record : Bool

  # Whether this item has been deleted from DynamoDB.
  property? destroyed : Bool

  @data : Hash(String, RawValue)
  @clean_copies : Hash(String, RawValue)
  @dirty_flags : Hash(String, Bool)

  # Creates the data of a new item, filled with its model's default values.
  #
  # With *track_mutations* off, the clean copies are the values themselves rather than deep copies,
  # so mutating a value in place goes unnoticed — the Ruby gem's `disable_mutation_tracking`.
  def initialize(@model_attributes : ModelAttributes, track_mutations : Bool = true) : Nil
    @data = {} of String => RawValue
    @clean_copies = {} of String => RawValue
    @dirty_flags = {} of String => Bool
    @track_mutations = track_mutations
    @new_record = true
    @destroyed = false
    populate_default_values
  end

  # The value of *name*, cast by its attribute's marshaler.
  def get_attribute(name : String | Symbol) : RawValue
    attribute = @model_attributes.attribute_for(name)
    return unless attribute
    attribute.type_cast(@data[name.to_s]?)
  end

  # Stores *value* for *name*, exactly as given.
  def set_attribute(name : String | Symbol, value : RawValue) : Nil
    @data[name.to_s] = value
  end

  # The value of *name* as it was assigned, without casting.
  def raw_value(name : String | Symbol) : RawValue
    @data[name.to_s]?
  end

  # Whether this item exists in DynamoDB as far as this instance knows.
  def persisted? : Bool
    !(new_record? || destroyed?)
  end

  # Marks every attribute as unchanged, remembering the current values as the clean ones.
  def clean! : Nil
    @dirty_flags.clear
    populate_default_values
    @model_attributes.attributes.each_key do |name|
      value = get_attribute(name)
      @clean_copies[name] = @track_mutations ? RawValues.deep_copy(value) : value
    end
  end

  # Whether *name* has changed since the item was last clean.
  def attribute_dirty?(name : String | Symbol) : Bool
    key = name.to_s
    return true if @dirty_flags[key]?
    get_attribute(key) != @clean_copies[key]?
  end

  # The value *name* had when the item was last clean.
  def attribute_was(name : String | Symbol) : RawValue
    @clean_copies[name.to_s]?
  end

  # Marks *name* as changed, whatever its value.
  def attribute_dirty!(name : String | Symbol) : Nil
    @dirty_flags[name.to_s] = true
  end

  # The names of every attribute that has changed since the item was last clean.
  def dirty : Array(String)
    @model_attributes.attributes.each_key.select { |name| attribute_dirty?(name) }.to_a
  end

  # Whether any attribute has changed since the item was last clean.
  def dirty? : Bool
    @model_attributes.attributes.each_key.any? { |name| attribute_dirty?(name) }
  end

  # Restores *name* to the value it had when the item was last clean, and returns it.
  def rollback_attribute!(name : String | Symbol) : RawValue
    key = name.to_s
    if attribute_dirty?(key)
      @dirty_flags.delete(key)
      set_attribute(key, attribute_was(key))
    end
    get_attribute(key)
  end

  # A copy of the raw values, as `#to_h` returns them.
  def hash_copy : Hash(String, RawValue)
    @data.dup
  end

  # The item to write to DynamoDB: every set attribute, serialized under its storage name.
  #
  # A `nil` value is left out unless its attribute asked to `persist_nil`.
  def build_save_hash : Aws::DynamoDB::Item
    item = Aws::DynamoDB::Item.new
    @data.each do |name, raw|
      attribute = @model_attributes.attribute_for(name)
      next unless attribute
      next if raw.nil? && !attribute.persist_nil?
      item[attribute.database_name] = attribute.serialize(raw)
    end
    item
  end

  # Fills in the default value of every attribute that has none set.
  def populate_default_values : Nil
    @model_attributes.attributes.each do |name, attribute|
      default = attribute.default_value
      next if default.nil?
      next unless @data[name]?.nil?
      @data[name] = default
    end
  end
end
