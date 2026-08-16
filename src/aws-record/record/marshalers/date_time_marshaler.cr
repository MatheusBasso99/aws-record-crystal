require "../time_parsing"
require "./marshaler"

# Marshals `datetime_attr` attributes.
#
# Values are converted to UTC unless `use_local_time` is set, and stored as
# `"2009-02-13T23:31:30+00:00"` — Ruby's `DateTime#iso8601`, which always writes a numeric offset,
# even for UTC.
class Aws::Record::Marshalers::DateTimeMarshaler < Aws::Record::Marshalers::Marshaler
  # What `#type_cast` produces.
  alias Cast = Time?

  # Formats a time the way Ruby's `DateTime#iso8601` does.
  ISO8601 = ->(time : Time) : String { time.to_s("%FT%T%:z") }

  # Creates the marshaler.
  #
  # *formatter* replaces the default `ISO8601` rendering, and *use_local_time* keeps the offset a
  # value was given with instead of converting it to UTC.
  def initialize(formatter : Proc(Time, String)? = nil, use_local_time : Bool = false) : Nil
    @formatter = formatter || ISO8601
    @use_local_time = use_local_time
  end

  # Casts *raw* to a `Time`, leaving `nil` and the empty string as `nil`.
  def type_cast(raw : RawValue) : RawValue
    cast(raw)
  end

  # Stores *raw* as an `S` attribute in the configured format.
  def serialize(raw : RawValue) : Aws::DynamoDB::Value
    cast(raw).try { |time| @formatter.call(time) }
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
           else              raise ArgumentError.new("expected a DateTime value or nil, got #{raw.class}")
           end
    return if time.nil?
    @use_local_time ? time : time.to_utc
  end
end
