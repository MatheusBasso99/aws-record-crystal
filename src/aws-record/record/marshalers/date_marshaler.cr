require "../time_parsing"
require "./marshaler"

# Marshals `date_attr` attributes.
#
# Crystal has no `Date`, so a date reads as a `Time` at midnight UTC on that day, and is stored as
# `"2015-11-25"` — the same `S` value the Ruby gem writes.
class Aws::Record::Marshalers::DateMarshaler < Aws::Record::Marshalers::Marshaler
  # What `#type_cast` produces.
  alias Cast = Time?

  # Formats a date the way Ruby's `Date#iso8601` does.
  ISO8601 = ->(date : Time) : String { date.to_s("%F") }

  # Creates the marshaler; *formatter* replaces the default `ISO8601` rendering.
  def initialize(formatter : Proc(Time, String)? = nil) : Nil
    @formatter = formatter || ISO8601
  end

  # Casts *raw* to the midnight of its calendar day, leaving `nil` and the empty string as `nil`.
  def type_cast(raw : RawValue) : RawValue
    cast(raw)
  end

  # Stores *raw* as an `S` attribute in the configured format.
  def serialize(raw : RawValue) : Aws::DynamoDB::Value
    cast(raw).try { |date| @formatter.call(date) }
  end

  # Recovers the cast type of *value*.
  def self.narrow(value : RawValue) : Cast
    value.as?(Time)
  end

  private def cast(raw : RawValue) : Time?
    case raw
    when Nil, "" then nil
    when Time    then midnight(raw)
    when Int64   then midnight(Time.unix(raw))
    when Number  then midnight(Time.unix(raw.to_i64))
    when String  then midnight(TimeParsing.parse(raw))
    else              raise ArgumentError.new("expected a Date value or nil, got #{raw.class}")
    end
  end

  private def midnight(time : Time) : Time
    Time.utc(time.year, time.month, time.day)
  end
end
