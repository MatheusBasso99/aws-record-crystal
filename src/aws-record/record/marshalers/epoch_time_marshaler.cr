require "../time_parsing"
require "./marshaler"

# Marshals `epoch_time_attr` attributes: times stored as an `N` attribute holding whole epoch
# seconds, which is the shape DynamoDB's Time to Live feature expects.
class Aws::Record::Marshalers::EpochTimeMarshaler < Aws::Record::Marshalers::Marshaler
  # What `#type_cast` produces.
  alias Cast = Time?

  # Creates the marshaler; *use_local_time* keeps the offset a value was given with.
  def initialize(use_local_time : Bool = false) : Nil
    @use_local_time = use_local_time
  end

  # Casts *raw* to a `Time`, leaving `nil` and the empty string as `nil`.
  def type_cast(raw : RawValue) : RawValue
    cast(raw)
  end

  # Stores *raw* as an `N` attribute holding epoch seconds.
  def serialize(raw : RawValue) : Aws::DynamoDB::Value
    cast(raw).try(&.to_unix)
  end

  # Recovers the cast type of *value*.
  def self.narrow(value : RawValue) : Cast
    value.as?(Time)
  end

  private def cast(raw : RawValue) : Time?
    time = case raw
           when Nil, "" then nil
           when Time    then raw
           when Int64   then Time.unix(raw)
           when Number  then Time.unix(raw.to_i64)
           when String  then TimeParsing.parse(raw)
           else              raise ArgumentError.new("expected a Time value or nil, got #{raw.class}")
           end
    return if time.nil?
    @use_local_time ? time : time.to_utc
  end
end
