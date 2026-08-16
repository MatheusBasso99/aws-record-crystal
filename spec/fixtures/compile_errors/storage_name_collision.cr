require "../../../src/aws-record-crystal"

class StorageNameCollision < Aws::Record::Base
  string_attr :a, database_attribute_name: "column_a"
  string_attr :column_a
end
