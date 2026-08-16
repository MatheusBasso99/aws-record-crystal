require "../../../src/aws-record-crystal"

class GsiMissingHashAttribute < Aws::Record::Base
  integer_attr :forum_id, hash_key: true

  global_secondary_index :fail, hash_key: :missingno, projection: {projection_type: "ALL"}
end
