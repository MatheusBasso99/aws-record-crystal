require "../../../src/aws-record-crystal"

class LsiMissingRangeKey < Aws::Record::Base
  integer_attr :forum_id, hash_key: true
  string_attr :post_title

  local_secondary_index :fail, projection: {projection_type: "ALL"}
end
