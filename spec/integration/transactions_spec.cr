require "../spec_helper"

module IntegrationSpec
  class TransactModel < Aws::Record::Base
    string_attr :uuid, hash_key: true
    string_attr :body
    string_attr :field
  end
end

private def transact_keys(*uuids : String) : Array(Hash(String, Aws::Record::RawValue))
  uuids.to_a.map { |uuid| Aws::Record::Base.raw_value_hash({uuid: uuid}) }
end

# The feature's Background: a PAY_PER_REQUEST table holding "a1" and "b2".
private def with_transact_table(& : Aws::DynamoDB::Client ->)
  with_model_config(IntegrationSpec::TransactModel) do |client, _name|
    config = local_table_config(IntegrationSpec::TransactModel, &.billing_mode("PAY_PER_REQUEST"))
    config.migrate!
    config.exact_match?.should be_true
    Aws::Record::Transactions.configure_client(client: client)
    IntegrationSpec::TransactModel.new(uuid: "a1", body: "First item!", field: "Foo").save!
    IntegrationSpec::TransactModel.new(uuid: "b2", body: "Lorem ipsum.", field: "Bar").save!
    yield client
  end
end

private def transact_model(record : Aws::Record::Base?) : IntegrationSpec::TransactModel
  record.should be_a(IntegrationSpec::TransactModel)
  record.as(IntegrationSpec::TransactModel)
end

# Ported from features/transactions/transactions.feature.
describe "Amazon DynamoDB Transactions", tags: "integration" do
  it "Get two items in a transaction (global)" do
    integration!
    with_transact_table do
      result = Aws::Record::Transactions.transact_find(
        transact_items: [
          IntegrationSpec::TransactModel.tfind_opts(key: {uuid: "a1"}),
          IntegrationSpec::TransactModel.tfind_opts(
            key: {uuid: "b2"},
            projection_expression: "#H, body",
            expression_attribute_names: {"#H" => "uuid"}
          ),
        ],
        return_consumed_capacity: "NONE"
      )

      result.responses.size.should eq(2)
      first = transact_model(result.responses[0])
      first.uuid.should eq("a1")
      first.body.should eq("First item!")
      first.field.should eq("Foo")

      second = transact_model(result.responses[1])
      second.uuid.should eq("b2")
      second.body.should eq("Lorem ipsum.")
      second.field.should be_nil
      result.missing_items.should be_empty
    end
  end

  it "Get two items in a transaction plus one missing (global)" do
    integration!
    with_transact_table do
      result = Aws::Record::Transactions.transact_find(transact_items: [
        IntegrationSpec::TransactModel.tfind_opts(key: {uuid: "a1"}),
        IntegrationSpec::TransactModel.tfind_opts(key: {uuid: "nope"}),
        IntegrationSpec::TransactModel.tfind_opts(key: {uuid: "b2"}),
      ])

      result.responses.size.should eq(3)
      transact_model(result.responses[0]).body.should eq("First item!")
      result.responses[1].should be_nil
      transact_model(result.responses[2]).body.should eq("Lorem ipsum.")

      result.missing_items.size.should eq(1)
      result.missing_items[0].model_class.should eq(IntegrationSpec::TransactModel)
      result.missing_items[0].key.should eq(Aws::DynamoDB::Item{"uuid" => "nope"})
    end
  end

  it "Get two items in a transaction plus one missing (class)" do
    integration!
    with_transact_table do
      result = IntegrationSpec::TransactModel.transact_find(transact_keys("a1", "nope", "b2"))

      result.responses.size.should eq(3)
      transact_model(result.responses[0]).field.should eq("Foo")
      result.responses[1].should be_nil
      transact_model(result.responses[2]).field.should eq("Bar")
      result.missing_items.size.should eq(1)
    end
  end

  it "Perform a transactional update (global)" do
    integration!
    with_transact_table do
      item1 = IntegrationSpec::TransactModel.find(uuid: "a1").should_not be_nil
      item1.body = "Updated a1!"
      item2 = IntegrationSpec::TransactModel.find(uuid: "b2").should_not be_nil
      item3 = IntegrationSpec::TransactModel.new(uuid: "c3", body: "New item!")
      Aws::Record::Transactions.transact_write(transact_items: [
        Aws::Record::Transactions.save(item1),
        Aws::Record::Transactions.save(item3),
        Aws::Record::Transactions.delete(item2),
      ])

      IntegrationSpec::TransactModel.find(uuid: "b2").should be_nil

      found = IntegrationSpec::TransactModel.find(uuid: "a1").should_not be_nil
      found.body.should eq("Updated a1!")
      found.field.should eq("Foo")

      created = IntegrationSpec::TransactModel.find(uuid: "c3").should_not be_nil
      created.body.should eq("New item!")
      created.field.should be_nil
    end
  end

  it "Perform a transactional set of puts and updates (global)" do
    integration!
    with_transact_table do
      item1 = IntegrationSpec::TransactModel.new(uuid: "a1", body: "Replaced!")
      item2 = IntegrationSpec::TransactModel.find(uuid: "b2").should_not be_nil
      item2.body = "Updated b2!"
      item3 = IntegrationSpec::TransactModel.new(uuid: "c3", body: "New item!")
      Aws::Record::Transactions.transact_write(transact_items: [
        Aws::Record::Transactions.put(item1),
        Aws::Record::Transactions.put(item3),
        Aws::Record::Transactions.update(item2),
      ])

      replaced = IntegrationSpec::TransactModel.find(uuid: "a1").should_not be_nil
      replaced.body.should eq("Replaced!")
      replaced.field.should be_nil

      updated = IntegrationSpec::TransactModel.find(uuid: "b2").should_not be_nil
      updated.body.should eq("Updated b2!")
      updated.field.should eq("Bar")

      created = IntegrationSpec::TransactModel.find(uuid: "c3").should_not be_nil
      created.body.should eq("New item!")
    end
  end

  it "Perform a transactional update with check (global)" do
    integration!
    with_transact_table do
      item1 = IntegrationSpec::TransactModel.find(uuid: "a1").should_not be_nil
      item1.body = "Passing the check!"
      check_exp = IntegrationSpec::TransactModel.transact_check_expression(
        key: {uuid: "b2"},
        condition_expression: "size(#T) <= :v",
        expression_attribute_names: {"#T" => "body"},
        expression_attribute_values: Aws::DynamoDB::Item{":v" => 1024_i64}
      )
      Aws::Record::Transactions.transact_write(transact_items: [
        Aws::Record::Transactions.save(item1),
        Aws::Record::Transactions.check(check_exp),
      ])

      found = IntegrationSpec::TransactModel.find(uuid: "a1").should_not be_nil
      found.body.should eq("Passing the check!")
      found.field.should eq("Foo")
    end
  end

  it "Perform a transactional update in error (global)" do
    integration!
    with_transact_table do
      item1 = IntegrationSpec::TransactModel.new(uuid: "a1", body: "Replaced!")
      item2 = IntegrationSpec::TransactModel.new(uuid: "b2", body: "Sneaky replacement!")
      item3 = IntegrationSpec::TransactModel.new(uuid: "c3", body: "New item!")

      expect_raises(Aws::DynamoDB::Errors::TransactionCanceledException) do
        Aws::Record::Transactions.transact_write(transact_items: [
          Aws::Record::Transactions.save(item1),
          Aws::Record::Transactions.save(item2),
          Aws::Record::Transactions.save(item3),
        ])
      end
    end
  end
end

# Parity: 7/7 scenarios from features/transactions/transactions.feature (aws-record 2.15.1)
