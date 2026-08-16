require "../../../src/aws-record-crystal"

class GsiMissingRangeAttribute < Aws::Record::Base
  integer_attr :forum_id, hash_key: true
  string_attr :forum_name

  global_secondary_index :fail, hash_key: :forum_name, range_key: :missingno,
    projection: {projection_type: "ALL"}
end
