require "../../../src/aws-record-crystal"

class StorageNameCollidesWithAttrName < Aws::Record::Base
  string_attr :dup_name, database_attribute_name: "dup_storage"
  string_attr :fail, database_attribute_name: "dup_name"
end
