require "../../spec_helper"

module TransactionsSpec
  class TableOne < Aws::Record::Base
    set_table_name "TableOne"
    integer_attr :id, hash_key: true
    string_attr :range, range_key: true
    string_attr :body
    string_attr :has_default, default_value: "Lorem ipsum."
  end

  class TableTwo < Aws::Record::Base
    set_table_name "TableTwo"
    string_attr :uuid, hash_key: true
    string_attr :body
    string_attr :has_default, default_value: "Lorem ipsum."
  end
end

private def transact_items(client : Aws::DynamoDB::Client) : JSON::Any
  api_requests(client)[0].params["TransactItems"]
end

describe Aws::Record::Transactions do
  describe "#transact_find" do
    it "uses tfind_opts to construct a request and returns modeled items" do
      client = stub_client
      client.stub_responses(:transact_get_items, Aws::DynamoDB::Types::TransactGetItemsOutput.new(
        responses: [
          Aws::DynamoDB::Types::ItemResponse.new(
            item: Aws::DynamoDB::Item{"id" => 1_i64, "range" => "a", "body" => "One"}
          ),
          Aws::DynamoDB::Types::ItemResponse.new(
            item: Aws::DynamoDB::Item{"uuid" => "foo", "body" => "Two"}
          ),
          Aws::DynamoDB::Types::ItemResponse.new(
            item: Aws::DynamoDB::Item{"id" => 2_i64, "range" => "b", "body" => "Three"}
          ),
        ]
      ))
      Aws::Record::Transactions.configure_client(client: client)

      items = Aws::Record::Transactions.transact_find(transact_items: [
        TransactionsSpec::TableOne.tfind_opts(key: {id: 1, range: "a"}),
        TransactionsSpec::TableTwo.tfind_opts(key: {uuid: "foo"}),
        TransactionsSpec::TableOne.tfind_opts(key: {id: 2, range: "b"}),
      ])

      items.responses.size.should eq(3)
      items.responses[0].should be_a(TransactionsSpec::TableOne)
      items.responses[1].should be_a(TransactionsSpec::TableTwo)
      items.responses[2].should be_a(TransactionsSpec::TableOne)
      items.responses.each(&.try(&.dirty?).should(be_false))
      items.responses[0].as(TransactionsSpec::TableOne).body.should eq("One")
      items.responses[1].as(TransactionsSpec::TableTwo).body.should eq("Two")
      items.responses[2].as(TransactionsSpec::TableOne).body.should eq("Three")
      items.missing_items.size.should eq(0)
    end

    it "handles and reports missing keys" do
      client = stub_client
      client.stub_responses(:transact_get_items, Aws::DynamoDB::Types::TransactGetItemsOutput.new(
        responses: [
          Aws::DynamoDB::Types::ItemResponse.new(
            item: Aws::DynamoDB::Item{"id" => 1_i64, "range" => "a", "body" => "One"}
          ),
          Aws::DynamoDB::Types::ItemResponse.new,
          Aws::DynamoDB::Types::ItemResponse.new(
            item: Aws::DynamoDB::Item{"id" => 2_i64, "range" => "b", "body" => "Three"}
          ),
        ]
      ))
      Aws::Record::Transactions.configure_client(client: client)

      items = Aws::Record::Transactions.transact_find(transact_items: [
        TransactionsSpec::TableOne.tfind_opts(key: {id: 1, range: "a"}),
        TransactionsSpec::TableTwo.tfind_opts(key: {uuid: "foo"}),
        TransactionsSpec::TableOne.tfind_opts(key: {id: 2, range: "b"}),
      ])

      items.responses.size.should eq(3)
      items.responses[1].should be_nil
      items.responses[0].should be_a(TransactionsSpec::TableOne)
      items.responses[2].should be_a(TransactionsSpec::TableOne)
      items.responses[0].as(TransactionsSpec::TableOne).body.should eq("One")
      items.responses[2].as(TransactionsSpec::TableOne).body.should eq("Three")
      items.missing_items.size.should eq(1)
      items.missing_items[0].model_class.should eq(TransactionsSpec::TableTwo)
      items.missing_items[0].key.should eq(Aws::DynamoDB::Item{"uuid" => "foo"})
    end

    it "raises when tfind_opts is missing a key" do
      Aws::Record::Transactions.configure_client(client: stub_client)
      expect_raises(Aws::Record::Errors::KeyMissing) do
        Aws::Record::Transactions.transact_find(transact_items: [
          TransactionsSpec::TableOne.tfind_opts(key: {range: "a"}),
          TransactionsSpec::TableTwo.tfind_opts(key: {uuid: "foo"}),
        ])
      end
    end
  end

  describe "#transact_write" do
    it "supports the basic update transaction types" do
      client = stub_client
      Aws::Record::Transactions.configure_client(client: client)

      put_item = TransactionsSpec::TableOne.new(id: 1, range: "a")
      update_item = TransactionsSpec::TableTwo.new(uuid: "foo")
      update_item.clean! # like we got it from #find
      update_item.body = "Content"
      delete_item = TransactionsSpec::TableOne.new(id: 2, range: "b")
      delete_item.clean! # like we got it from #find

      put_item.dirty?.should be_true
      update_item.dirty?.should be_true
      delete_item.destroyed?.should be_false

      Aws::Record::Transactions.transact_write(transact_items: [
        Aws::Record::Transactions.put(put_item),
        Aws::Record::Transactions.update(update_item),
        Aws::Record::Transactions.delete(delete_item),
      ])

      put_item.dirty?.should be_false
      update_item.dirty?.should be_false
      delete_item.destroyed?.should be_true
      api_requests(client).size.should eq(1)
      transact_items(client).should eq(
        JSON.parse(
          %([{"Put":{"TableName":"TableOne","Item":{"has_default":{"S":"Lorem ipsum."},) +
          %("id":{"N":"1"},"range":{"S":"a"}}}},) +
          %({"Update":{"TableName":"TableTwo","Key":{"uuid":{"S":"foo"}},) +
          %("UpdateExpression":"SET #UE_A = :ue_a","ExpressionAttributeNames":{"#UE_A":"body"},) +
          %("ExpressionAttributeValues":{":ue_a":{"S":"Content"}}}},) +
          %({"Delete":{"TableName":"TableOne","Key":{"id":{"N":"2"},"range":{"S":"b"}}}}])
        )
      )
    end

    it "supports manually defined check operations" do
      client = stub_client
      Aws::Record::Transactions.configure_client(client: client)

      check = TransactionsSpec::TableOne.transact_check_expression(
        key: {id: 10, range: "z"},
        condition_expression: "size(#T) <= :v",
        expression_attribute_names: {"#T" => "body"},
        expression_attribute_values: Aws::DynamoDB::Item{":v" => 1024_i64}
      )
      put_item = TransactionsSpec::TableOne.new(id: 1, range: "a")

      Aws::Record::Transactions.transact_write(transact_items: [
        Aws::Record::Transactions.check(check),
        Aws::Record::Transactions.put(put_item),
      ])

      api_requests(client).size.should eq(1)
      transact_items(client).should eq(
        JSON.parse(
          %([{"ConditionCheck":{"TableName":"TableOne","Key":{"id":{"N":"10"},"range":{"S":"z"}},) +
          %("ConditionExpression":"size(#T) <= :v","ExpressionAttributeNames":{"#T":"body"},) +
          %("ExpressionAttributeValues":{":v":{"N":"1024"}}}},) +
          %({"Put":{"TableName":"TableOne","Item":{"has_default":{"S":"Lorem ipsum."},) +
          %("id":{"N":"1"},"range":{"S":"a"}}}}])
        )
      )
    end

    it "supports transactional save as an update or safe put" do
      client = stub_client
      Aws::Record::Transactions.configure_client(client: client)

      put_item = TransactionsSpec::TableOne.new(id: 1, range: "a")
      update_item = TransactionsSpec::TableTwo.new(uuid: "foo")
      update_item.clean! # like we got it from #find
      update_item.body = "Content"

      put_item.dirty?.should be_true
      update_item.dirty?.should be_true

      Aws::Record::Transactions.transact_write(transact_items: [
        Aws::Record::Transactions.save(put_item),
        Aws::Record::Transactions.save(update_item),
      ])

      put_item.dirty?.should be_false
      update_item.dirty?.should be_false
      api_requests(client).size.should eq(1)
      transact_items(client).should eq(
        JSON.parse(
          %([{"Put":{"TableName":"TableOne","Item":{"has_default":{"S":"Lorem ipsum."},) +
          %("id":{"N":"1"},"range":{"S":"a"}},) +
          %("ConditionExpression":"attribute_not_exists(#H) and attribute_not_exists(#R)",) +
          %("ExpressionAttributeNames":{"#H":"id","#R":"range"}}},) +
          %({"Update":{"TableName":"TableTwo","Key":{"uuid":{"S":"foo"}},) +
          %("UpdateExpression":"SET #UE_A = :ue_a","ExpressionAttributeNames":{"#UE_A":"body"},) +
          %("ExpressionAttributeValues":{":ue_a":{"S":"Content"}}}}])
        )
      )
    end

    it "supports additional options per transaction" do
      client = stub_client
      Aws::Record::Transactions.configure_client(client: client)

      put_item = TransactionsSpec::TableOne.new(id: 1, range: "a")
      update_item = TransactionsSpec::TableTwo.new(uuid: "foo")
      update_item.clean!
      update_item.body = "Content"
      delete_item = TransactionsSpec::TableOne.new(id: 2, range: "b")
      delete_item.clean!
      save_item = TransactionsSpec::TableOne.new(id: 3, range: "c")

      Aws::Record::Transactions.transact_write(transact_items: [
        Aws::Record::Transactions.put(put_item, return_values_on_condition_check_failure: "ALL_OLD"),
        Aws::Record::Transactions.update(update_item, return_values_on_condition_check_failure: "ALL_OLD"),
        Aws::Record::Transactions.delete(delete_item, return_values_on_condition_check_failure: "ALL_OLD"),
        Aws::Record::Transactions.save(save_item, return_values_on_condition_check_failure: "ALL_OLD"),
      ])

      api_requests(client).size.should eq(1)
      items = transact_items(client).as_a
      items.size.should eq(4)
      items.each { |item| item.as_h.first_value["ReturnValuesOnConditionCheckFailure"].should eq("ALL_OLD") }
      items[3]["Put"]["ConditionExpression"]
        .should eq("attribute_not_exists(#H) and attribute_not_exists(#R)")
    end

    it "can combine expression attributes for update" do
      client = stub_client
      Aws::Record::Transactions.configure_client(client: client)

      update_item = TransactionsSpec::TableTwo.new(uuid: "foo")
      update_item.clean!
      update_item.body = "Content"
      save_item = TransactionsSpec::TableTwo.new(uuid: "bar")
      save_item.clean!
      save_item.body = "Content"

      Aws::Record::Transactions.transact_write(transact_items: [
        Aws::Record::Transactions.update(
          update_item,
          condition_expression: "size(#T) <= :v",
          expression_attribute_names: {"#T" => "body"},
          expression_attribute_values: Aws::DynamoDB::Item{":v" => 1024_i64},
          return_values_on_condition_check_failure: "ALL_OLD"
        ),
        Aws::Record::Transactions.save(
          save_item,
          condition_expression: "size(#T) <= :v",
          expression_attribute_names: {"#T" => "body"},
          expression_attribute_values: Aws::DynamoDB::Item{":v" => 1024_i64},
          return_values_on_condition_check_failure: "ALL_OLD"
        ),
      ])

      items = transact_items(client).as_a
      items.size.should eq(2)
      items.each do |item|
        update = item["Update"]
        update["UpdateExpression"].should eq("SET #UE_A = :ue_a")
        update["ConditionExpression"].should eq("size(#T) <= :v")
        update["ExpressionAttributeNames"].should eq(JSON.parse(%({"#UE_A":"body","#T":"body"})))
        update["ExpressionAttributeValues"]
          .should eq(JSON.parse(%({":ue_a":{"S":"Content"},":v":{"N":"1024"}})))
      end
    end

    it "supports custom update expressions" do
      client = stub_client
      Aws::Record::Transactions.configure_client(client: client)

      update_item = TransactionsSpec::TableTwo.new(uuid: "foo")
      update_item.clean!

      Aws::Record::Transactions.transact_write(transact_items: [
        Aws::Record::Transactions.update(
          update_item,
          update_expression: "SET #S = if_not_exists(#S, :s)",
          expression_attribute_names: {"#S" => "body"},
          expression_attribute_values: Aws::DynamoDB::Item{":s" => "Content"}
        ),
      ])

      transact_items(client).should eq(
        JSON.parse(
          %([{"Update":{"TableName":"TableTwo","Key":{"uuid":{"S":"foo"}},) +
          %("UpdateExpression":"SET #S = if_not_exists(#S, :s)",) +
          %("ExpressionAttributeNames":{"#S":"body"},) +
          %("ExpressionAttributeValues":{":s":{"S":"Content"}}}}])
        )
      )
    end

    it "raises a validation exception when safe put collides with a condition expression" do
      Aws::Record::Transactions.configure_client(client: stub_client)
      save_item = TransactionsSpec::TableTwo.new(uuid: "bar", body: "Content")
      save_item.dirty?.should be_true

      expect_raises(Aws::Record::Errors::TransactionalSaveConditionCollision) do
        Aws::Record::Transactions.transact_write(transact_items: [
          Aws::Record::Transactions.save(
            save_item,
            condition_expression: "size(#T) <= :v",
            expression_attribute_names: {"#T" => "body"},
            expression_attribute_values: Aws::DynamoDB::Item{":v" => 1024_i64}
          ),
        ])
      end
      save_item.dirty?.should be_true
    end

    it "raises an exception when attribute updates collide with an update expression" do
      Aws::Record::Transactions.configure_client(client: stub_client)
      update_item = TransactionsSpec::TableTwo.new(uuid: "foo")
      update_item.clean!
      update_item.body = "Content"

      expect_raises(Aws::Record::Errors::UpdateExpressionCollision) do
        Aws::Record::Transactions.transact_write(transact_items: [
          Aws::Record::Transactions.update(
            update_item,
            update_expression: "SET #H = :v",
            expression_attribute_names: {"#H" => "has_default"},
            expression_attribute_values: Aws::DynamoDB::Item{":v" => "other"}
          ),
        ])
      end
    end

    it "does not clean items when the transaction fails" do
      client = stub_client
      client.stub_responses(:transact_write_items, "TransactionCanceledException")
      Aws::Record::Transactions.configure_client(client: client)

      put_item = TransactionsSpec::TableOne.new(id: 1, range: "a")
      update_item = TransactionsSpec::TableTwo.new(uuid: "foo")
      update_item.clean!
      update_item.body = "Content"
      delete_item = TransactionsSpec::TableOne.new(id: 2, range: "b")
      delete_item.clean!

      put_item.dirty?.should be_true

      expect_raises(Aws::DynamoDB::Errors::TransactionCanceledException) do
        Aws::Record::Transactions.transact_write(transact_items: [
          Aws::Record::Transactions.put(put_item),
          Aws::Record::Transactions.update(update_item),
          Aws::Record::Transactions.delete(delete_item),
        ])
      end

      put_item.dirty?.should be_true
      update_item.dirty?.should be_true
      delete_item.destroyed?.should be_false
    end
  end
end

# Parity: 12/12 examples from spec/aws-record/record/transactions_spec.rb (aws-record 2.15.1)
