require "../../../src/aws-record-crystal"

class InvalidAssignAttributes < Aws::Record::Base
  string_attr :mykey, hash_key: true
  string_attr :body
end

InvalidAssignAttributes.new.assign_attributes(mykey_key: "ThrowsError")
