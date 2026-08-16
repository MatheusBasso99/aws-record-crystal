require "../src/aws-record-crystal"

class MyModel < Aws::Record::Base
  integer_attr :id, hash_key: true
  string_attr :name, range_key: true
  boolean_attr :active, database_attribute_name: "is_active_flag"
end

config = Aws::Record::TableConfig.define do |table|
  table.model_class(MyModel)
  table.read_capacity_units(5)
  table.write_capacity_units(2)
end
config.migrate!

if found = MyModel.find(id: 1, name: "Hello Record")
  found.active = true
  found.save
  found.delete!
end

MyModel.find(id: 1, name: "Hello Record") # => nil

item = MyModel.new
item.id = 2
item.name = "Item"
item.active = false
item.save

MyModel.scan(consistent_read: true).each { |record| puts record.to_h }

MyModel.build_query
  .key_expr(":id = ? AND :name > ?", 1, "b")
  .filter_expr(":active = ?", true)
  .consistent_read(true)
  .complete!
