require "../../../src/aws-record-crystal"

class DuplicateStorageName < Aws::Record::Base
  string_attr :a, database_attribute_name: "unique"
  string_attr :b, database_attribute_name: "unique"
end
