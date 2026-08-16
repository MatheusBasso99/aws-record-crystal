require "../src/aws-record-crystal"

class Breakfast < Aws::Record::Base
  integer_attr :id, hash_key: true
  string_attr :name, range_key: true
  string_attr :body
end

eggs = Breakfast.new(id: 1, name: "eggs")
eggs.save!
waffles = Breakfast.new(id: 2, name: "waffles")
pancakes = Breakfast.new(id: 3, name: "pancakes")

write = Aws::Record::Batch.write(client: Breakfast.dynamodb_client) do |db|
  db.put(waffles)
  db.delete(eggs)
  db.put(pancakes)
end

# Unprocessed items are retried by calling `execute!` again:
until write.complete?
  write.execute!
end
