require "../../../src/aws-record-crystal"

class AttrNameCollidesWithStorageName < Aws::Record::Base
  string_attr :dup_name, database_attribute_name: "dup_storage"
  string_attr :dup_storage, database_attribute_name: "fail"
end
