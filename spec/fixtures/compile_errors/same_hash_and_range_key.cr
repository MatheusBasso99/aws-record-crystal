require "../../../src/aws-record-crystal"

class SameHashAndRangeKey < Aws::Record::Base
  string_attr :oops, hash_key: true, range_key: true
end
