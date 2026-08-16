# Parses the date and time strings the Ruby gem accepts.
#
# Ruby's `Date.parse` and `Time.parse` are very lenient; Crystal's are strict and each handles one
# format, so the marshalers go through this cascade instead. It covers RFC 3339, the
# `"2016-07-20 16:31:10 -0700"` and `"2009-02-13 23:31:30 UTC"` spellings the Ruby specs use, plain
# `"%F %T"`, date-only strings (which `Time.parse_iso8601` rejects), RFC 2822 and epoch seconds.
#
# ```
# Aws::Record::TimeParsing.parse("2015-11-25") # => 2015-11-25 00:00:00 UTC
# ```
module Aws::Record::TimeParsing
  extend self

  # The formats tried, in order, after RFC 3339.
  FORMATS = {
    "%F %T %z",
    "%FT%T%z",
    "%F %T %Z",
    "%FT%T%Z",
    "%F %T",
    "%FT%T",
    "%F",
    "%a, %d %b %Y %H:%M:%S %z",
    "%Y/%m/%d",
  }

  # Parses *value* into a `Time`.
  #
  # Raises `ArgumentError` when no known format matches, as Ruby's `Date.parse`/`Time.parse` do.
  def parse(value : String) : Time
    stripped = value.strip
    raise ArgumentError.new("Invalid date/time value: #{value.inspect}") if stripped.empty?
    parse?(stripped) || raise ArgumentError.new("Invalid date/time value: #{value.inspect}")
  end

  # Parses *value* into a `Time`, or returns `nil` when no known format matches.
  def parse?(value : String) : Time?
    if time = rfc3339?(value)
      return time
    end
    FORMATS.each do |format|
      if time = formatted?(value, format)
        return time
      end
    end
    epoch?(value)
  end

  private def rfc3339?(value) : Time?
    Time.parse_rfc3339(value)
  rescue Time::Format::Error
    nil
  end

  private def formatted?(value, format) : Time?
    Time.parse(value, format, Time::Location::UTC)
  rescue Time::Format::Error
    nil
  end

  private def epoch?(value) : Time?
    seconds = value.to_i64?
    seconds ? Time.unix(seconds) : nil
  end
end
