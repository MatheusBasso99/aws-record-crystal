require "../../../src/aws-record-crystal"

class IncrementNonInteger < Aws::Record::Base
  integer_attr :id, hash_key: true
  atomic_counter :counter
end

IncrementNonInteger.new(id: 1).increment_counter!("foo")
