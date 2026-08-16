require "../../../src/aws-record-crystal"

class LsiMissingAttribute < Aws::Record::Base
  integer_attr :forum_id, hash_key: true

  local_secondary_index :fail, range_key: :missingno, projection: {projection_type: "ALL"}
end
