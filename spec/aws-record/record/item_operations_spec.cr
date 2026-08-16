require "../../spec_helper"

module ItemOperationsSpec
  class TestModel < Aws::Record::Base
    set_table_name "TestTable"
    integer_attr :id, hash_key: true
    date_attr :date, range_key: true, database_attribute_name: "MyDate"
    string_attr :body
    string_attr :persist_on_nil, persist_nil: true
    list_attr :list_nil_to_empty, default_value: [] of Aws::DynamoDB::Value
    list_attr :list_nil_as_nil, persist_nil: true
    list_attr :list_no_nil_persist
    map_attr :map_nil_to_empty, default_value: Aws::DynamoDB::Item.new
    map_attr :map_nil_as_nil, persist_nil: true
    map_attr :map_no_nil_persist
    boolean_attr :bool, database_attribute_name: "my_boolean"
    epoch_time_attr :ttl
  end

  class DefaultsModel < Aws::Record::Base
    set_table_name "TestTable"
    string_attr :mykey, hash_key: true
    map_attr :dirty_map, default_value: Aws::DynamoDB::Item.new
  end

  # The Ruby spec brings in ActiveModel::Validations; here `#valid?` is the hook, as documented.
  class ValidatedModel < Aws::Record::Base
    set_table_name "TestTable"
    integer_attr :id, hash_key: true
    date_attr :date, range_key: true
    string_attr :body
    boolean_attr :bool, database_attribute_name: "my_boolean"

    def valid? : Bool
      !id.nil? && !date.nil?
    end
  end
end

private def configured(client = stub_client)
  ItemOperationsSpec::TestModel.configure_client(client: client)
  client
end

private def new_item(id : Int32 = 1, date : String = "2015-12-14") : ItemOperationsSpec::TestModel
  item = ItemOperationsSpec::TestModel.new
  item.id = id
  item.date = date
  item
end

private def key_hash(**values) : Hash(String, Aws::Record::RawValue)
  Aws::Record::Base.raw_value_hash(values)
end

private def safe_put_json(item_json : String) : JSON::Any
  JSON.parse(
    %({"TableName":"TestTable","Item":#{item_json},) +
    %("ConditionExpression":"attribute_not_exists(#H) and attribute_not_exists(#R)",) +
    %("ExpressionAttributeNames":{"#H":"id","#R":"MyDate"}})
  )
end

describe "ItemOperations" do
  describe "#save!" do
    it "can save an item that does not yet exist to Amazon DynamoDB" do
      client = configured
      item = new_item
      item.body = "Hello!"
      item.ttl = Time.utc(2018, 7, 9, 22, 2, 12)
      item.save!

      api_requests(client).map(&.params).should eq([
        safe_put_json(
          %({"list_nil_to_empty":{"L":[]},"map_nil_to_empty":{"M":{}},"id":{"N":"1"},) +
          %("MyDate":{"S":"2015-12-14"},"body":{"S":"Hello!"},"ttl":{"N":"1531173732"}})
        ),
      ])
    end

    it "passes through options to #update_item and #put_item" do
      client = configured
      item = new_item
      item.body = "Hello!"
      item.save!(table_name: "notused", return_values: "ALL_OLD")
      item.save!(force: true, table_name: "notused", return_values: "UPDATED_OLD")
      item.save!(table_name: "notused", return_values: "ALL_NEW")
      item.clean!
      item.body = "Goodbye!"
      item.save!(table_name: "notused", return_values: "UPDATED_NEW")

      requests = api_requests(client)
      requests.map(&.params.["TableName"].as_s).should eq(["TestTable"] * 4)
      requests.map(&.params.["ReturnValues"].as_s)
        .should eq(["ALL_OLD", "UPDATED_OLD", "ALL_NEW", "UPDATED_NEW"])
    end

    it "raises an error when you try to save! without setting keys" do
      client = configured
      no_keys = ItemOperationsSpec::TestModel.new
      expect_raises(Aws::Record::Errors::KeyMissing, "Missing required keys: id, date") { no_keys.save! }

      no_hash = ItemOperationsSpec::TestModel.new
      no_hash.date = "2015-12-15"
      expect_raises(Aws::Record::Errors::KeyMissing, "Missing required keys: id") { no_hash.save! }

      no_range = ItemOperationsSpec::TestModel.new
      no_range.id = 5
      expect_raises(Aws::Record::Errors::KeyMissing, "Missing required keys: date") { no_range.save! }

      api_requests(client).should be_empty
    end
  end

  describe "#save" do
    it "can save an item that does not yet exist to Amazon DynamoDB" do
      client = configured
      item = new_item
      item.body = "Hello!"
      item.new_record?.should be_true
      item.save
      item.new_record?.should be_false

      api_requests(client).map(&.params).should eq([
        safe_put_json(
          %({"list_nil_to_empty":{"L":[]},"map_nil_to_empty":{"M":{}},"id":{"N":"1"},) +
          %("MyDate":{"S":"2015-12-14"},"body":{"S":"Hello!"}})
        ),
      ])
    end

    it "will call #put_item without conditions if :force is included" do
      client = configured
      item = new_item
      item.body = "Hello!"
      item.save(force: true)

      api_requests(client).map(&.params).should eq([
        JSON.parse(
          %({"TableName":"TestTable","Item":{"list_nil_to_empty":{"L":[]},"map_nil_to_empty":{"M":{}},) +
          %("id":{"N":"1"},"MyDate":{"S":"2015-12-14"},"body":{"S":"Hello!"}}})
        ),
      ])
    end

    it "will call #update_item for changes to existing items" do
      client = configured
      item = new_item
      item.body = "Hello!"
      item.clean! # I'm claiming that it is this way in the DB now.
      item.body = "Goodbye!"
      item.save

      api_requests(client).map(&.params).should eq([
        JSON.parse(
          %({"TableName":"TestTable","Key":{"id":{"N":"1"},"MyDate":{"S":"2015-12-14"}},) +
          %("UpdateExpression":"SET #UE_A = :ue_a","ExpressionAttributeNames":{"#UE_A":"body"},) +
          %("ExpressionAttributeValues":{":ue_a":{"S":"Goodbye!"}}})
        ),
      ])
    end

    it "will call #update_item with pass through update expression for existing items" do
      client = configured
      item = new_item
      item.body = "Hello!"
      item.clean! # I'm claiming that it is this way in the DB now.
      item.save(
        update_expression: "SET #S = if_not_exists(#S, :s)",
        expression_attribute_names: {"#S" => "body"},
        expression_attribute_values: Aws::DynamoDB::Item{":s" => "Goodbye!"}
      )

      api_requests(client).map(&.params).should eq([
        JSON.parse(
          %({"TableName":"TestTable","Key":{"id":{"N":"1"},"MyDate":{"S":"2015-12-14"}},) +
          %("UpdateExpression":"SET #S = if_not_exists(#S, :s)",) +
          %("ExpressionAttributeNames":{"#S":"body"},) +
          %("ExpressionAttributeValues":{":s":{"S":"Goodbye!"}}})
        ),
      ])
    end

    it "passes through options to #update_item and #put_item" do
      client = configured
      item = new_item
      item.body = "Hello!"
      item.save(table_name: "notused", return_values: "ALL_OLD")
      item.save(force: true, table_name: "notused", return_values: "UPDATED_OLD")
      item.save(table_name: "notused", return_values: "ALL_NEW")
      item.clean!
      item.body = "Goodbye!"
      item.save(table_name: "notused", return_values: "UPDATED_NEW")

      requests = api_requests(client)
      requests.map(&.params.["TableName"].as_s).should eq(["TestTable"] * 4)
      requests.map(&.params.["ReturnValues"].as_s)
        .should eq(["ALL_OLD", "UPDATED_OLD", "ALL_NEW", "UPDATED_NEW"])
    end

    it "raises an exception when the conditional check fails" do
      client = configured
      client.stub_responses(:put_item, "ConditionalCheckFailedException")
      item = new_item
      item.body = "Hello!"

      error = expect_raises(Aws::Record::Errors::ConditionalWriteFailed) { item.save }
      error.original_error.should be_a(Aws::DynamoDB::Errors::ConditionalCheckFailedException)

      api_requests(client).map(&.params).should eq([
        safe_put_json(
          %({"list_nil_to_empty":{"L":[]},"map_nil_to_empty":{"M":{}},"id":{"N":"1"},) +
          %("MyDate":{"S":"2015-12-14"},"body":{"S":"Hello!"}})
        ),
      ])
    end

    it "raises a key missing error when you try to save without setting keys" do
      client = configured
      no_keys = ItemOperationsSpec::TestModel.new
      expect_raises(Aws::Record::Errors::KeyMissing, "Missing required keys: id, date") { no_keys.save }

      no_hash = ItemOperationsSpec::TestModel.new
      no_hash.date = "2015-12-15"
      expect_raises(Aws::Record::Errors::KeyMissing, "Missing required keys: id") { no_hash.save }

      no_range = ItemOperationsSpec::TestModel.new
      no_range.id = 5
      expect_raises(Aws::Record::Errors::KeyMissing, "Missing required keys: date") { no_range.save }

      api_requests(client).should be_empty
    end

    it "raises an exception when attribute updates collide with an update expression" do
      configured
      item = new_item
      item.body = "Hello!"
      item.clean! # I'm claiming that it is this way in the DB now.
      item.body = "Goodbye!"

      expect_raises(Aws::Record::Errors::UpdateExpressionCollision) do
        item.save(
          update_expression: "SET #S = if_not_exists(#S, :s)",
          expression_attribute_names: {"#S" => "body"},
          expression_attribute_values: Aws::DynamoDB::Item{":s" => "Goodbye!"}
        )
      end
    end

    describe "modifications to default values" do
      it "persists modifications to default values" do
        client = stub_client
        ItemOperationsSpec::DefaultsModel.configure_client(client: client)
        item = ItemOperationsSpec::DefaultsModel.new(mykey: "key")
        item.dirty_map.try { |map| map["a"] = 1_i64 }
        item.save

        api_requests(client).map(&.params).should eq([
          JSON.parse(
            %({"TableName":"TestTable","Item":{"dirty_map":{"M":{"a":{"N":"1"}}},"mykey":{"S":"key"}},) +
            %("ConditionExpression":"attribute_not_exists(#H)",) +
            %("ExpressionAttributeNames":{"#H":"mykey"}})
          ),
        ])
      end
    end
  end

  describe "#find" do
    it "can read an item from Amazon DynamoDB" do
      client = configured
      client.stub_responses(
        :get_item,
        Aws::DynamoDB::Types::GetItemOutput.new(
          item: Aws::DynamoDB::Item{"id" => 5_i64, "MyDate" => "2015-12-15", "my_boolean" => true}
        )
      )

      found = ItemOperationsSpec::TestModel.find(id: 5, date: "2015-12-15")
      api_requests(client).map(&.params).should eq([
        JSON.parse(%({"TableName":"TestTable","Key":{"id":{"N":"5"},"MyDate":{"S":"2015-12-15"}}})),
      ])

      found = found.should_not be_nil
      found.should be_a(ItemOperationsSpec::TestModel)
      found.id.should eq(5)
      found.date.should eq(Time.utc(2015, 12, 15))
      found.bool.should be_true
      found.new_record?.should be_false
      found.persisted?.should be_true
    end

    it "enforces that the required keys are present" do
      configured
      expect_raises(Aws::Record::Errors::KeyMissing) { ItemOperationsSpec::TestModel.find(id: 5) }
    end
  end

  describe "#find_with_opts" do
    it "can read an item from Amazon DynamoDB" do
      client = configured
      client.stub_responses(
        :get_item,
        Aws::DynamoDB::Types::GetItemOutput.new(
          item: Aws::DynamoDB::Item{"id" => 5_i64, "MyDate" => "2015-12-15", "my_boolean" => true}
        )
      )

      found = ItemOperationsSpec::TestModel.find_with_opts(key: {id: 5, date: "2015-12-15"})
      api_requests(client).map(&.params).should eq([
        JSON.parse(%({"TableName":"TestTable","Key":{"id":{"N":"5"},"MyDate":{"S":"2015-12-15"}}})),
      ])

      found = found.should_not be_nil
      found.should be_a(ItemOperationsSpec::TestModel)
      found.id.should eq(5)
      found.date.should eq(Time.utc(2015, 12, 15))
      found.bool.should be_true
      found.new_record?.should be_false
      found.persisted?.should be_true
    end

    it "enforces that the required keys are present" do
      configured
      expect_raises(Aws::Record::Errors::KeyMissing) do
        ItemOperationsSpec::TestModel.find_with_opts(key: {id: 5})
      end
    end

    it "passes through options to #get_item" do
      client = configured
      ItemOperationsSpec::TestModel.find_with_opts(key: {id: 5, date: "2015-12-15"}, consistent_read: true)
      api_requests(client)[0].params["ConsistentRead"].should be_true
    end
  end

  describe "#find_all" do
    it "passes the correct client, class and key arguments to BatchRead" do
      # Rewritten without mocks: the Ruby spec stubs `Batch.read`, this asserts the request it makes.
      client = configured
      client.stub_responses(
        :batch_get_item,
        Aws::DynamoDB::Types::BatchGetItemOutput.new(
          responses: {"TestTable" => [Aws::DynamoDB::Item{"id" => 1_i64, "MyDate" => "2022-12-24"}]}
        )
      )

      keys = [
        key_hash(id: 1, date: "2022-12-24"),
        key_hash(id: 2, date: "2022-12-25"),
        key_hash(id: 3, date: "2022-12-26"),
      ]
      result = ItemOperationsSpec::TestModel.find_all(keys)

      result.should be_a(Aws::Record::BatchRead)
      api_requests(client)[0].params.should eq(
        JSON.parse(
          %({"RequestItems":{"TestTable":{"Keys":[) +
          %({"id":{"N":"1"},"MyDate":{"S":"2022-12-24"}},) +
          %({"id":{"N":"2"},"MyDate":{"S":"2022-12-25"}},) +
          %({"id":{"N":"3"},"MyDate":{"S":"2022-12-26"}}]}}})
        )
      )
      result.items.size.should eq(1)
      result.items[0].should be_a(ItemOperationsSpec::TestModel)
    end
  end

  describe ".update" do
    it "can find and update an item from Amazon DynamoDB" do
      client = configured
      ItemOperationsSpec::TestModel.update(id: 1, date: "2016-05-18", body: "New", bool: true)

      api_requests(client).map(&.params).should eq([
        JSON.parse(
          %({"TableName":"TestTable","Key":{"id":{"N":"1"},"MyDate":{"S":"2016-05-18"}},) +
          %("UpdateExpression":"SET #UE_A = :ue_a, #UE_B = :ue_b",) +
          %("ExpressionAttributeNames":{"#UE_A":"body","#UE_B":"my_boolean"},) +
          %("ExpressionAttributeValues":{":ue_a":{"S":"New"},":ue_b":{"BOOL":true}}})
        ),
      ])
    end

    it "can find item and apply update if update expression provided" do
      client = configured
      ItemOperationsSpec::TestModel.update(
        {id: 1, date: "2016-05-18"},
        update_expression: "SET #S = if_not_exists(#S, :s)",
        expression_attribute_names: {"#S" => "body"},
        expression_attribute_values: Aws::DynamoDB::Item{":s" => "Content"}
      )

      api_requests(client).map(&.params).should eq([
        JSON.parse(
          %({"TableName":"TestTable","Key":{"id":{"N":"1"},"MyDate":{"S":"2016-05-18"}},) +
          %("UpdateExpression":"SET #S = if_not_exists(#S, :s)",) +
          %("ExpressionAttributeNames":{"#S":"body"},) +
          %("ExpressionAttributeValues":{":s":{"S":"Content"}}})
        ),
      ])
    end

    it "will recognize nil as a removal operation if nil not persisted" do
      client = configured
      ItemOperationsSpec::TestModel.update(id: 1, date: "2016-07-20", body: nil, persist_on_nil: nil)

      api_requests(client).map(&.params).should eq([
        JSON.parse(
          %({"TableName":"TestTable","Key":{"id":{"N":"1"},"MyDate":{"S":"2016-07-20"}},) +
          %("UpdateExpression":"SET #UE_B = :ue_b REMOVE #UE_A",) +
          %("ExpressionAttributeNames":{"#UE_A":"body","#UE_B":"persist_on_nil"},) +
          %("ExpressionAttributeValues":{":ue_b":{"NULL":true}}})
        ),
      ])
    end

    it "will recognize nil as a removal operation even if it is the only operation" do
      client = configured
      ItemOperationsSpec::TestModel.update(id: 1, date: "2016-07-20", body: nil)

      api_requests(client).map(&.params).should eq([
        JSON.parse(
          %({"TableName":"TestTable","Key":{"id":{"N":"1"},"MyDate":{"S":"2016-07-20"}},) +
          %("UpdateExpression":"REMOVE #UE_A","ExpressionAttributeNames":{"#UE_A":"body"}})
        ),
      ])
    end

    it "will upsert even if only keys provided" do
      client = configured
      ItemOperationsSpec::TestModel.update(id: 1, date: "2016-05-18")

      api_requests(client).map(&.params).should eq([
        JSON.parse(%({"TableName":"TestTable","Key":{"id":{"N":"1"},"MyDate":{"S":"2016-05-18"}}})),
      ])
    end

    it "raises if any key attributes are missing" do
      configured
      expect_raises(Aws::Record::Errors::KeyMissing) do
        ItemOperationsSpec::TestModel.update(id: 5, body: "Fail")
      end
    end

    it "raises if both attribute updates and update expression provided" do
      configured
      expect_raises(Aws::Record::Errors::UpdateExpressionCollision) do
        ItemOperationsSpec::TestModel.update(
          {id: 1, date: "2016-05-18", bool: false},
          update_expression: "SET #S = if_not_exists(#S, :s)",
          expression_attribute_names: {"#S" => "body"},
          expression_attribute_values: Aws::DynamoDB::Item{":s" => "Content"}
        )
      end
    end
  end

  describe "#save_values" do
    it "returns the item that would be written, keyed by storage name" do
      configured
      item = new_item
      item.body = "Hello!"
      item.save_values.should eq(
        Aws::DynamoDB::Item{
          "list_nil_to_empty" => [] of Aws::DynamoDB::Value,
          "map_nil_to_empty"  => Aws::DynamoDB::Item.new,
          "id"                => 1_i64,
          "MyDate"            => "2015-12-14",
          "body"              => "Hello!",
        }
      )
    end

    it "raises when a key attribute has no value" do
      configured
      expect_raises(Aws::Record::Errors::KeyMissing) { ItemOperationsSpec::TestModel.new.save_values }
    end
  end

  describe "#delete!" do
    it "can delete an item from Amazon DynamoDB" do
      client = configured
      item = new_item(3, "2015-12-17")

      item.delete!.should be_true
      item.destroyed?.should be_true
      api_requests(client).map(&.params).should eq([
        JSON.parse(%({"TableName":"TestTable","Key":{"id":{"N":"3"},"MyDate":{"S":"2015-12-17"}}})),
      ])
    end

    it "passes through options to #delete_item" do
      client = configured
      item = new_item(3, "2015-12-17")
      item.delete!(table_name: "notused", return_values: "ALL_OLD")

      api_requests(client)[0].params["TableName"].should eq("TestTable")
      api_requests(client)[0].params["ReturnValues"].should eq("ALL_OLD")
    end
  end

  describe "save after delete scenarios" do
    it "sets destroyed to false after saving a destroyed record" do
      configured
      item = new_item(3, "2015-12-17")
      item.delete!.should be_true
      item.destroyed?.should be_true
      item.save
      item.destroyed?.should be_false
    end
  end

  describe "nil persistence scenarios" do
    it "does not persist attributes that are not defined" do
      client = configured
      new_item.save

      api_requests(client).map(&.params).should eq([
        safe_put_json(
          %({"list_nil_to_empty":{"L":[]},"map_nil_to_empty":{"M":{}},"id":{"N":"1"},) +
          %("MyDate":{"S":"2015-12-14"}})
        ),
      ])
    end

    it "does not persist nil attributes by default" do
      client = configured
      item = new_item
      item.body = nil
      item.persist_on_nil = nil
      item.save

      api_requests(client).map(&.params).should eq([
        safe_put_json(
          %({"list_nil_to_empty":{"L":[]},"map_nil_to_empty":{"M":{}},"id":{"N":"1"},) +
          %("MyDate":{"S":"2015-12-14"},"persist_on_nil":{"NULL":true}})
        ),
      ])
    end

    it "can persist nil list and map attributes as default values" do
      client = configured
      item = new_item
      item.list_nil_to_empty = nil
      item.map_nil_to_empty = nil
      item.list_no_nil_persist = nil
      item.map_no_nil_persist = nil
      item.save

      api_requests(client).map(&.params).should eq([
        safe_put_json(
          %({"list_nil_to_empty":{"L":[]},"map_nil_to_empty":{"M":{}},"id":{"N":"1"},) +
          %("MyDate":{"S":"2015-12-14"}})
        ),
      ])
    end

    it "can persist nil list and map attributes as nil" do
      client = configured
      item = new_item
      item.list_nil_as_nil = nil
      item.map_nil_as_nil = nil
      item.list_no_nil_persist = nil
      item.map_no_nil_persist = nil
      item.save

      api_requests(client).map(&.params).should eq([
        safe_put_json(
          %({"list_nil_to_empty":{"L":[]},"map_nil_to_empty":{"M":{}},"id":{"N":"1"},) +
          %("MyDate":{"S":"2015-12-14"},"list_nil_as_nil":{"NULL":true},"map_nil_as_nil":{"NULL":true}})
        ),
      ])
    end

    it "correctly reads nil collections from DynamoDB" do
      client = configured
      client.stub_responses(
        :get_item,
        Aws::DynamoDB::Types::GetItemOutput.new(
          item: Aws::DynamoDB::Item{
            "id"                => 5_i64,
            "MyDate"            => "2016-07-15",
            "list_nil_to_empty" => nil,
            "list_nil_as_nil"   => nil,
            "map_nil_to_empty"  => nil,
            "map_nil_as_nil"    => nil,
          }
        )
      )

      item = ItemOperationsSpec::TestModel.find(id: 5, date: "2016-07-15").should_not be_nil
      item.list_nil_to_empty.should eq([] of Aws::DynamoDB::Value)
      item.list_nil_as_nil.should be_nil
      item.map_nil_to_empty.should eq(Aws::DynamoDB::Item.new)
      item.map_nil_as_nil.should be_nil
    end
  end

  describe "validations with ActiveModel::Validations" do
    it "will use ActiveModel::Validations :valid? method" do
      ItemOperationsSpec::ValidatedModel.configure_client(client: stub_client)
      item = ItemOperationsSpec::ValidatedModel.new
      item.id = 3
      item.save.should be_false
      item.date = "2016-04-21"
      item.body = "Hello!"
      item.save.should be_true
    end

    it "will raise on an invalid model for #save!" do
      ItemOperationsSpec::ValidatedModel.configure_client(client: stub_client)
      item = ItemOperationsSpec::ValidatedModel.new
      item.id = 3
      expect_raises(Aws::Record::Errors::ValidationError, "Validation hook returned false!") { item.save! }
    end
  end

  describe "Transactional APIs" do
    describe "#transact_find" do
      it "can directly call #transact_find" do
        client = configured
        client.stub_responses(:transact_get_items, Aws::DynamoDB::Types::TransactGetItemsOutput.new(
          responses: [
            Aws::DynamoDB::Types::ItemResponse.new(
              item: Aws::DynamoDB::Item{"id" => 1_i64, "MyDate" => "2015-12-14", "body" => "One"}
            ),
            Aws::DynamoDB::Types::ItemResponse.new,
            Aws::DynamoDB::Types::ItemResponse.new(
              item: Aws::DynamoDB::Item{"id" => 2_i64, "MyDate" => "2018-11-29", "body" => "Three"}
            ),
          ]
        ))

        keys = [
          key_hash(id: 1, date: "2015-12-14"),
          key_hash(id: 7, date: "2019-07-14"),
          key_hash(id: 2, date: "2018-11-29"),
        ]
        items = ItemOperationsSpec::TestModel.transact_find(keys)

        api_requests(client).size.should eq(1)
        api_requests(client)[0].params["TransactItems"].should eq(
          JSON.parse(
            %([{"Get":{"TableName":"TestTable","Key":{"id":{"N":"1"},"MyDate":{"S":"2015-12-14"}}}},) +
            %({"Get":{"TableName":"TestTable","Key":{"id":{"N":"7"},"MyDate":{"S":"2019-07-14"}}}},) +
            %({"Get":{"TableName":"TestTable","Key":{"id":{"N":"2"},"MyDate":{"S":"2018-11-29"}}}}])
          )
        )

        items.responses.size.should eq(3)
        items.responses[1].should be_nil
        items.responses[0].should be_a(ItemOperationsSpec::TestModel)
        items.responses[2].should be_a(ItemOperationsSpec::TestModel)
        items.responses[0].as(ItemOperationsSpec::TestModel).body.should eq("One")
        items.responses[2].as(ItemOperationsSpec::TestModel).body.should eq("Three")
        items.missing_items.size.should eq(1)
        items.missing_items[0].model_class.should eq(ItemOperationsSpec::TestModel)
        items.missing_items[0].key
          .should eq(Aws::DynamoDB::Item{"id" => 7_i64, "MyDate" => "2019-07-14"})
      end
    end
  end

  describe "#transact_check_expression" do
    it "can create a valid check expression" do
      expression = ItemOperationsSpec::TestModel.transact_check_expression(
        key: {id: 10, date: "2018-11-29"},
        condition_expression: "size(#T) <= :v",
        expression_attribute_names: {"#T" => "body"},
        expression_attribute_values: Aws::DynamoDB::Item{":v" => 1024_i64}
      )

      expression.key.should eq(Aws::DynamoDB::Item{"id" => 10_i64, "MyDate" => "2018-11-29"})
      expression.table_name.should eq("TestTable")
      expression.condition_expression.should eq("size(#T) <= :v")
      expression.expression_attribute_names.should eq({"#T" => "body"})
      expression.expression_attribute_values.should eq(Aws::DynamoDB::Item{":v" => 1024_i64})
    end
  end
end

# Parity: 37/37 examples from spec/aws-record/record/item_operations_spec.rb (aws-record 2.15.1),
# plus extras. `#find_all` and `#transact_find` are rewritten without mocks, against the stub client.
