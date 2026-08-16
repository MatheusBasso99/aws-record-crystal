require "../src/aws-record-crystal"

class TableOne < Aws::Record::Base
  string_attr :uuid, hash_key: true
  string_attr :body
end

class TableTwo < Aws::Record::Base
  string_attr :hk, hash_key: true
  string_attr :rk, range_key: true
  string_attr :body
end

results = Aws::Record::Transactions.transact_find(transact_items: [
  TableOne.tfind_opts(key: {uuid: "uuid1234"}),
  TableTwo.tfind_opts(key: {hk: "hk1", rk: "rk1"}),
  TableTwo.tfind_opts(key: {hk: "hk2", rk: "rk2"}),
])
# `results.responses` holds an item or nil per request; `results.missing_items` says which were missing.
results.responses.map(&.class) # => [TableOne, TableTwo, TableTwo]

check = TableOne.transact_check_expression(
  key: {uuid: "foo"},
  condition_expression: "size(#T) <= :v",
  expression_attribute_names: {"#T" => "body"},
  expression_attribute_values: Aws::DynamoDB::Item{":v" => 1024_i64}
)
new_item = TableTwo.new(hk: "hk1", rk: "rk1", body: "Hello!")
put_item = TableOne.new(uuid: "foobar", body: "Content!")

actions = [
  Aws::Record::Transactions.check(check),
  Aws::Record::Transactions.save(new_item),
  Aws::Record::Transactions.put(
    put_item,
    condition_expression: "attribute_not_exists(#H)",
    expression_attribute_names: {"#H" => "uuid"},
    return_values_on_condition_check_failure: "ALL_OLD"
  ),
]

if updated = TableOne.find(uuid: "bar")
  updated.body = "Updated the body!"
  actions << Aws::Record::Transactions.save(updated)
end
if doomed = TableOne.find(uuid: "to_be_deleted")
  actions << Aws::Record::Transactions.delete(doomed)
end

Aws::Record::Transactions.transact_write(transact_items: actions)
