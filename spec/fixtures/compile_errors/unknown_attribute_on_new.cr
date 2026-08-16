require "../../../src/aws-record-crystal"

class UnknownAttributeOnNew < Aws::Record::Base
  string_attr :id, hash_key: true
end

UnknownAttributeOnNew.new(nope: "x")
