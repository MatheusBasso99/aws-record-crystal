require "../../../src/aws-record-crystal"

class DuplicateAttrName < Aws::Record::Base
  string_attr :duplication
  datetime_attr :duplication
end
