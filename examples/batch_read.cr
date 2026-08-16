require "../src/aws-record-crystal"

class Lunch < Aws::Record::Base
  integer_attr :id, hash_key: true
  string_attr :name, range_key: true
end

class Dessert < Aws::Record::Base
  integer_attr :id, hash_key: true
  string_attr :name, range_key: true
end

read = Aws::Record::Batch.read do |db|
  db.find(Lunch, id: 1, name: "Papaya Salad")
  db.find(Lunch, id: 2, name: "BLT Sandwich")
  db.find(Dessert, id: 1, name: "Apple Pie")
end

# BatchRead is Enumerable and handles pagination. Items come back as `Aws::Record::Base`,
# so narrow them to reach the typed accessors:
read.each do |item|
  puts item.name if item.is_a?(Lunch)
end

# BatchRead also has a lower level interface: `execute!`, `complete?` and `items`.
# Unprocessed keys are retried by calling `execute!` again:
until read.complete?
  read.execute!
end
