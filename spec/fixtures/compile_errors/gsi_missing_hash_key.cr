require "../../../src/aws-record-crystal"

class GsiMissingHashKey < Aws::Record::Base
  integer_attr :forum_id, hash_key: true

  global_secondary_index :fail, projection: {projection_type: "ALL"}
end
