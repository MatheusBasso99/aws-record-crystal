require "./marshalers/marshaler"
require "./raw_value"

# One attribute of a model: its name, how it is named and typed in DynamoDB, how it is marshaled,
# and what it defaults to.
#
# Instances are built by the `*_attr` macros; models rarely construct one directly.
class Aws::Record::Attribute
  # The attribute name, as the model declares it.
  getter name : String

  # The attribute name as stored in DynamoDB, which `database_attribute_name` can change.
  getter database_name : String

  # The DynamoDB scalar type (`"S"`, `"N"`, `"B"`, …), needed for key and index attributes.
  getter dynamodb_type : String?

  # The marshaler that casts and serializes this attribute's values.
  getter marshaler : Marshalers::Marshaler

  @default_value : RawValue
  @default_value_proc : Proc(RawValue)?
  @has_default_value : Bool
  @persist_nil : Bool

  # Creates an attribute.
  #
  # *default_value_set* is what tells `default_value: nil` apart from no default at all, which the
  # Ruby gem gets from `options.key?(:default_value)`: an explicit `nil` is type cast (so a set
  # attribute defaults to an empty set), a missing one stays `nil`.
  def initialize(
    name : String | Symbol,
    @marshaler : Marshalers::Marshaler = Marshalers::DefaultMarshaler.new,
    database_attribute_name : (String | Symbol)? = nil,
    @dynamodb_type : String? = nil,
    persist_nil : Bool = false,
    default_value : RawValue = nil,
    default_value_set : Bool = false,
    @default_value_proc : Proc(RawValue)? = nil,
  ) : Nil
    @name = name.to_s
    @database_name = (database_attribute_name || name).to_s
    @persist_nil = persist_nil
    @has_default_value = default_value_set || !@default_value_proc.nil?
    @default_value = default_value_set ? @marshaler.type_cast(default_value) : nil
  end

  # Wraps a block returning any value into the `Proc(RawValue)` a lazy default value needs.
  #
  # Crystal infers a proc literal's type from what its body actually returns, so
  # `->{ 2 + 3 }` is a `Proc(Int32)` and does not fit `default_value_proc`; this widens it.
  #
  # ```
  # Aws::Record::Attribute.new(:created_at, default_value_proc: Aws::Record::Attribute.default_proc { Time.utc })
  # ```
  def self.default_proc(&block : -> T) : Proc(RawValue) forall T
    Proc(RawValue).new { RawValues.from(block.call) }
  end

  # The value *raw* reads as: the marshaler's cast, or the default when that is `nil`.
  def type_cast(raw : RawValue) : RawValue
    cast = @marshaler.type_cast(raw)
    cast.nil? ? default_value : cast
  end

  # The value *raw* is stored as, or `nil` when it should not be persisted.
  def serialize(raw : RawValue) : Aws::DynamoDB::Value
    cast = type_cast(raw)
    cast = default_value if cast.nil?
    @marshaler.serialize(cast)
  end

  # Whether a `nil` value is written as `NULL` instead of being left out.
  def persist_nil? : Bool
    @persist_nil
  end

  # This attribute's value in *item*, keyed by its `#database_name`.
  def extract(item : Aws::DynamoDB::Item) : Aws::DynamoDB::Value
    item[@database_name]?
  end

  # This attribute's default value.
  #
  # A default given as a proc is called — and its result type cast — on every read, and a mutable
  # default is deep copied, so that one item's default can never be mutated through another's.
  def default_value : RawValue
    if proc = @default_value_proc
      return type_cast_default(proc.call)
    end
    return @default_value if RawValues.immutable?(@default_value)
    RawValues.deep_copy(@default_value)
  end

  # Whether a default value was configured at all.
  def default_value? : Bool
    @has_default_value
  end

  private def type_cast_default(value : RawValue) : RawValue
    @marshaler.type_cast(value)
  end
end
