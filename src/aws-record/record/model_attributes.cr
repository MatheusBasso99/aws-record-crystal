require "./attribute"
require "./errors"

# The attributes of a model, by name and by storage name.
#
# Attribute macros build one of these per model class; it is reachable as `Model.attributes`.
class Aws::Record::ModelAttributes
  # Every attribute of the model, in declaration order, keyed by attribute name.
  getter attributes : Hash(String, Attribute)

  # The attribute name each DynamoDB storage name maps back to.
  getter storage_attributes : Hash(String, String)

  # Creates an empty set of attributes.
  def initialize : Nil
    @attributes = {} of String => Attribute
    @storage_attributes = {} of String => String
  end

  # Adds *attribute*, refusing names that collide with an existing attribute or storage name.
  #
  # Raises `Errors::NameCollision` for any of the three collisions the Ruby gem checks for.
  def register_attribute(attribute : Attribute) : Attribute
    validate(attribute)
    @attributes[attribute.name] = attribute
    @storage_attributes[attribute.database_name] = attribute.name
    attribute
  end

  # The attribute called *name*, or `nil`.
  def attribute_for(name : String | Symbol) : Attribute?
    @attributes[name.to_s]?
  end

  # The DynamoDB storage name of the attribute called *name*.
  #
  # Raises `KeyError` when there is no such attribute.
  def storage_name_for(name : String | Symbol) : String
    attribute = attribute_for(name)
    raise KeyError.new("No such attribute #{name}") unless attribute
    attribute.database_name
  end

  # Whether the model has an attribute called *name*.
  def present?(name : String | Symbol) : Bool
    !attribute_for(name).nil?
  end

  # The attribute name stored under *storage_name*, or `nil`.
  def db_to_attribute_name(storage_name : String) : String?
    @storage_attributes[storage_name]?
  end

  private def validate(attribute) : Nil
    name = attribute.name
    storage_name = attribute.database_name
    if @attributes[name]?
      raise Errors::NameCollision.new("Cannot overwrite existing attribute #{name}")
    elsif @attributes[storage_name]? && storage_name != name
      raise Errors::NameCollision.new(
        "Custom storage name #{storage_name} already exists as an attribute name in #{@attributes.keys}"
      )
    elsif (existing = @storage_attributes[name]?) && existing != name
      raise Errors::NameCollision.new(
        "Attribute name #{name} already exists as a custom storage name in #{@storage_attributes}"
      )
    elsif @storage_attributes[storage_name]?
      raise Errors::NameCollision.new(
        "Custom storage name #{storage_name} already in use in #{@storage_attributes}"
      )
    end
  end
end

# The hash and range key of a model.
class Aws::Record::KeyAttributes
  # The keys by role: `:hash` and, when there is one, `:range`.
  getter keys : Hash(Symbol, String)

  # Creates an empty key set over *model_attributes*.
  def initialize(@model_attributes : ModelAttributes) : Nil
    @keys = {} of Symbol => String
  end

  # The name of the hash key attribute, or `nil` when the model has none.
  def hash_key : String?
    @keys[:hash]?
  end

  # The hash key attribute, or `nil`.
  def hash_key_attribute : Attribute?
    hash_key.try { |name| @model_attributes.attribute_for(name) }
  end

  # Sets the hash key attribute name.
  def hash_key=(value : String) : String
    @keys[:hash] = value
  end

  # The name of the range key attribute, or `nil` when the model has none.
  def range_key : String?
    @keys[:range]?
  end

  # The range key attribute, or `nil`.
  def range_key_attribute : Attribute?
    range_key.try { |name| @model_attributes.attribute_for(name) }
  end

  # Sets the range key attribute name.
  def range_key=(value : String) : String
    @keys[:range] = value
  end
end

# A model's attributes and keys, built once per model class.
#
# The two are memoized together so that a model never has one without the other.
class Aws::Record::ModelDefinition
  # The model's attributes.
  getter attributes : ModelAttributes

  # The model's keys.
  getter keys : KeyAttributes

  # Creates a definition.
  def initialize(@attributes : ModelAttributes, @keys : KeyAttributes) : Nil
  end

  # An empty definition, used by models that declare no attributes.
  def self.empty : ModelDefinition
    attributes = ModelAttributes.new
    new(attributes, KeyAttributes.new(attributes))
  end
end
