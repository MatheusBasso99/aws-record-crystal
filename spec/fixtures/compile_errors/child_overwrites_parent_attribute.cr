require "../../../src/aws-record-crystal"

class OverwriteParent < Aws::Record::Base
  string_attr :name, hash_key: true
end

class OverwriteChild < OverwriteParent
  integer_attr :name
end
