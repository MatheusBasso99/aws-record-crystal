require "../../spec_helper"
require "uuid"

module DirtyTrackingSpec
  class TestModel < Aws::Record::Base
    set_table_name :test_table
    string_attr :mykey, hash_key: true
    string_attr :body
  end

  # The Ruby spec repeats a group with `include ActiveModel::Model`, which brings a `#persisted?`
  # of its own; Crystal has no such library, so the model is the same shape.
  class ActiveModelLike < Aws::Record::Base
    set_table_name :test_table
    string_attr :mykey, hash_key: true
    string_attr :body
  end

  class ValidatedModel < Aws::Record::Base
    set_table_name "TestTable"
    integer_attr :id, hash_key: true
    string_attr :body

    def valid? : Bool
      (body.try(&.size) || 0) <= 5
    end
  end

  class MutationModel < Aws::Record::Base
    set_table_name :test_table
    string_attr :mykey, hash_key: true
    string_attr :body
    list_attr :dirty_list
    map_attr :dirty_map
    string_set_attr :dirty_set
  end

  class DefaultsModel < Aws::Record::Base
    set_table_name :test_table
    string_attr :mykey, hash_key: true
    map_attr :dirty_map, default_value: Aws::DynamoDB::Item.new
  end

  class TrackingOffModel < Aws::Record::Base
    set_table_name :test_table
    string_attr :mykey, hash_key: true
    list_attr :dirty_list
  end
end

private def instance : DirtyTrackingSpec::TestModel
  DirtyTrackingSpec::TestModel.new
end

private def uuid : String
  UUID.random.to_s
end

private def list(*values : Int32) : Array(Aws::DynamoDB::Value)
  # Built element by element: `Tuple#map` types its block against `Union(*T)`, which does not unify
  # with the recursive `Value` alias.
  result = Array(Aws::DynamoDB::Value).new(values.size)
  values.each { |value| result << value.to_i64 }
  result
end

describe Aws::Record::Base do
  describe "#[attribute]_dirty?" do
    it "should return whether the attribute is dirty or clean" do
      item = instance
      item.mykey_dirty?.should be_false
      item.mykey = uuid
      item.mykey_dirty?.should be_true
    end

    it "should not reflect changes to the original value as dirty" do
      item = instance
      item.mykey = nil
      item.mykey_dirty?.should be_false
      item.mykey = uuid
      item.mykey_dirty?.should be_true
      item.mykey = nil
      item.mykey_dirty?.should be_false
    end

    it "should recognize initialization values as dirty" do
      item = DirtyTrackingSpec::TestModel.new(mykey: "Key", body: "Hello!")
      item.mykey_dirty?.should be_true
    end
  end

  describe "#[attribute]_dirty!" do
    it "should mark the attribute as dirty" do
      item = instance
      item.mykey = "Alex"
      item.clean!

      item.mykey_dirty?.should be_false
      item.mykey_dirty!
      item.mykey_dirty?.should be_true
      item.mykey = "s"
      item.mykey_dirty?.should be_true
    end

    it "should take a snapshot of the attribute" do
      item = instance
      item.mykey = "Alex"
      item.clean!

      item.mykey_was.should eq("Alex")
      item.mykey.should eq("Alex")
      item.mykey = "Alexi"
      item.mykey_was.should eq("Alex")
      item.mykey.should eq("Alexi")
      item.mykey_dirty!
      item.mykey_was.should eq("Alex")
      item.mykey.should eq("Alexi")
      item.mykey = "Alexis"
      item.mykey_was.should eq("Alex")
      item.mykey.should eq("Alexis")
    end
  end

  describe "#[attribute]_was" do
    it "should return the last known clean value" do
      item = instance
      item.mykey_was.should be_nil
      item.mykey = uuid
      item.mykey_was.should be_nil
    end
  end

  describe "#clean!" do
    it "should mark the record as clean" do
      item = instance
      item.mykey = uuid
      item.dirty?.should be_true
      item.mykey_was.should be_nil
      item.clean!
      item.dirty?.should be_false
      item.mykey_was.should eq(item.mykey)
    end
  end

  describe "#dirty" do
    it "should return an array of dirty attributes" do
      item = instance
      item.dirty.should be_empty
      item.mykey = uuid
      item.dirty.should eq(["mykey"])
      item.body = uuid
      item.dirty.sort.should eq(["body", "mykey"])
    end
  end

  describe "#dirty?" do
    it "should return whether the record is dirty or clean" do
      item = instance
      item.dirty?.should be_false
      item.mykey = uuid
      item.dirty?.should be_true
    end
  end

  describe "#reload!" do
    it "can reload an item using find" do
      # Rewritten without mocks: the Ruby spec stubs `.find`, this stubs `get_item` underneath it.
      client = stub_client
      DirtyTrackingSpec::TestModel.configure_client(client: client)
      key = uuid
      stored_body = uuid
      client.stub_responses(
        :get_item,
        Aws::DynamoDB::Types::GetItemOutput.new(
          item: Aws::DynamoDB::Item{"mykey" => key, "body" => stored_body}
        )
      )

      item = instance
      item.mykey = key
      item.body = uuid
      item.reload!
      item.body.should eq(stored_body)
      api_requests(client)[0].params["Key"]["mykey"]["S"].should eq(key)
    end

    it "raises an error when find returns nil" do
      client = stub_client
      DirtyTrackingSpec::TestModel.configure_client(client: client)
      client.stub_responses(:get_item, Aws::DynamoDB::Types::GetItemOutput.new)

      item = instance
      item.mykey = uuid
      expect_raises(Aws::Record::Errors::NotFound, "No record found") { item.reload! }
    end

    it "should mark the item as clean" do
      client = stub_client
      DirtyTrackingSpec::TestModel.configure_client(client: client)
      key = uuid
      client.stub_responses(
        :get_item,
        Aws::DynamoDB::Types::GetItemOutput.new(item: Aws::DynamoDB::Item{"mykey" => key})
      )

      item = instance
      item.mykey = key
      item.dirty?.should be_true
      item.reload!
      item.dirty?.should be_false
    end
  end

  describe "persisted?" do
    it "appropriately determines whether an item is persisted" do
      DirtyTrackingSpec::TestModel.configure_client(client: stub_client)
      item = instance
      item.mykey = "mykey"
      item.body = "body"
      item.persisted?.should be_false
      item.save
      item.persisted?.should be_true
      item.delete!
      item.persisted?.should be_false

      other = instance
      other.mykey = "mykey"
      other.body = "body"
      other.delete!
      other.persisted?.should be_false
    end
  end

  describe "persisted? with ActiveModel::Model" do
    it "appropriately determines whether an item is persisted" do
      DirtyTrackingSpec::ActiveModelLike.configure_client(client: stub_client)
      item = DirtyTrackingSpec::ActiveModelLike.new
      item.mykey = "mykey"
      item.body = "body"
      item.persisted?.should be_false
      item.save
      item.persisted?.should be_true
      item.delete!
      item.persisted?.should be_false

      other = DirtyTrackingSpec::ActiveModelLike.new
      other.mykey = "mykey"
      other.body = "body"
      other.delete!
      other.persisted?.should be_false
    end
  end

  describe "#rollback_[attribute]!" do
    it "should restore the attribute to its last known clean value" do
      item = instance
      original = item.mykey
      item.mykey = uuid
      item.rollback_mykey!
      item.mykey.should eq(original)
    end
  end

  describe "#rollback!" do
    it "should restore the provided attributes" do
      item = instance
      original = item.mykey
      item.mykey = uuid
      updated_body = uuid
      item.body = updated_body
      item.rollback!(:mykey)
      item.mykey.should eq(original)
      item.body.should eq(updated_body)
    end

    describe "when no attributes are provided" do
      it "should restore all attributes" do
        item = instance
        original_key = item.mykey
        original_body = item.body
        item.mykey = uuid
        item.body = uuid
        item.rollback!
        item.dirty?.should be_false
        item.mykey.should eq(original_key)
        item.body.should eq(original_body)
      end
    end
  end

  describe "#update" do
    it "assign_attributes should perform a hash based attribute assignment without persisting changes" do
      DirtyTrackingSpec::TestModel.configure_client(client: stub_client)
      item = instance
      item.mykey = "mykey"
      item.body = "body"
      item.save

      item.assign_attributes(mykey: "newkey", body: "newbody")
      item.mykey.should eq("newkey")
      item.body.should eq("newbody")
      item.dirty?.should be_true
    end

    it "update should perform a hash based attribute assignment and persist changes" do
      DirtyTrackingSpec::TestModel.configure_client(client: stub_client)
      item = instance
      item.mykey = "mykey"
      item.body = "body"
      item.save

      item.update(mykey: "newkey", body: "newbody")
      item.mykey.should eq("newkey")
      item.body.should eq("newbody")
      item.dirty?.should be_false
    end

    it "automatically tokenizes update hash keys" do
      # Crystal keyword arguments are already symbols; there is nothing to tokenize.
      DirtyTrackingSpec::TestModel.configure_client(client: stub_client)
      item = instance
      item.mykey = "mykey"
      item.body = "body"
      item.save

      item.update(mykey: "newkey", body: "newbody")
      item.mykey.should eq("newkey")
      item.body.should eq("newbody")
      item.dirty?.should be_false
    end

    it "update not update when an invalid update is performed" do
      DirtyTrackingSpec::ValidatedModel.configure_client(client: stub_client)
      record = DirtyTrackingSpec::ValidatedModel.new(id: 1, body: "12345")
      record.save
      record.update(body: "123456").should be_false
    end

    it "update! should throw an error when a validation error occurs" do
      DirtyTrackingSpec::ValidatedModel.configure_client(client: stub_client)
      record = DirtyTrackingSpec::ValidatedModel.new(id: 1, body: "12345")
      record.save
      expect_raises(Aws::Record::Errors::ValidationError) { record.update!(body: "123456") }
    end

    it "should throw an argument error when you try to update an invalid attribute" do
      expect_compile_error("invalid_assign_attributes.cr", "Invalid field: mykey_key")
    end
  end

  describe "#update with ActiveModel::Model" do
    it "assign_attributes should perform a hash based attribute assignment without persisting changes" do
      DirtyTrackingSpec::ActiveModelLike.configure_client(client: stub_client)
      item = DirtyTrackingSpec::ActiveModelLike.new(mykey: "mykey", body: "body")
      item.save

      item.assign_attributes(mykey: "newkey", body: "newbody")
      item.mykey.should eq("newkey")
      item.body.should eq("newbody")
      item.dirty?.should be_true
    end

    it "update should perform a hash based attribute assignment and persist changes" do
      DirtyTrackingSpec::ActiveModelLike.configure_client(client: stub_client)
      item = DirtyTrackingSpec::ActiveModelLike.new(mykey: "mykey", body: "body")
      item.save

      item.update(mykey: "newkey", body: "newbody")
      item.mykey.should eq("newkey")
      item.body.should eq("newbody")
      item.dirty?.should be_false
    end

    it "automatically tokenizes update hash keys" do
      DirtyTrackingSpec::ActiveModelLike.configure_client(client: stub_client)
      item = DirtyTrackingSpec::ActiveModelLike.new(mykey: "mykey", body: "body")
      item.save

      item.update(mykey: "newkey", body: "newbody")
      item.mykey.should eq("newkey")
      item.body.should eq("newbody")
      item.dirty?.should be_false
    end

    it "update! should throw an error when a validation error occurs" do
      DirtyTrackingSpec::ValidatedModel.configure_client(client: stub_client)
      record = DirtyTrackingSpec::ValidatedModel.new(id: 1, body: "12345")
      record.save
      expect_raises(Aws::Record::Errors::ValidationError) { record.update!(body: "123456") }
    end

    it "should throw an argument error when you try to update an invalid attribute" do
      expect_compile_error("invalid_assign_attributes.cr", "Invalid field: mykey_key")
    end
  end

  describe "#save" do
    it "should mark the item as clean" do
      DirtyTrackingSpec::TestModel.configure_client(client: stub_client)
      item = instance
      item.mykey = uuid
      item.dirty?.should be_true
      item.save
      item.dirty?.should be_false
    end
  end

  describe "#find" do
    it "should mark the item as clean" do
      client = stub_client
      DirtyTrackingSpec::TestModel.configure_client(client: client)
      client.stub_responses(
        :get_item,
        Aws::DynamoDB::Types::GetItemOutput.new(item: Aws::DynamoDB::Item{"mykey" => "1"})
      )

      found = DirtyTrackingSpec::TestModel.find(mykey: "1").should_not be_nil
      found.dirty?.should be_false
    end
  end

  describe "Mutation Dirty Tracking" do
    describe "Default Values" do
      it "tracks mutations to the default value" do
        item = DirtyTrackingSpec::DefaultsModel.new(mykey: "key")
        item.clean!
        item.dirty?.should be_false
        item.dirty_map.try { |map| map["key"] = "value" }
        item.dirty_map.should eq(Aws::DynamoDB::Item{"key" => "value"})
        item.dirty?.should be_true
      end
    end

    describe "Tracking Turned Off" do
      it "does not track detailed mutations when tracking is globally off" do
        DirtyTrackingSpec::TrackingOffModel.disable_mutation_tracking
        item = DirtyTrackingSpec::TrackingOffModel.new(mykey: "1", dirty_list: list(1, 2, 3))
        item.clean!
        item.dirty_list.try(&.<<(4_i64))
        item.dirty_list.should eq(list(1, 2, 3, 4))
        item.dirty?.should be_false
      ensure
        DirtyTrackingSpec::TrackingOffModel.enable_mutation_tracking
      end
    end

    describe "Lists" do
      it "marks mutated lists as dirty" do
        item = DirtyTrackingSpec::MutationModel.new(mykey: "1", dirty_list: list(1, 2, 3))
        item.clean!
        item.dirty_list.try(&.<<(4_i64))
        item.dirty_list.should eq(list(1, 2, 3, 4))
        item.dirty?.should be_true
        item.attribute_dirty?(:dirty_list).should be_true
      end

      it "has a copy of the mutated list to reference and can roll back" do
        item = DirtyTrackingSpec::MutationModel.new(mykey: "1", dirty_list: list(1, 2, 3))
        item.clean!
        item.dirty_list.try(&.<<(4_i64))
        item.dirty_list_was.should eq(list(1, 2, 3))
        item.rollback!(:dirty_list)
        item.dirty_list.should eq(list(1, 2, 3))
      end

      it "includes the mutated list in the list of dirty attributes" do
        item = DirtyTrackingSpec::MutationModel.new(mykey: "1", body: "b", dirty_list: list(1, 2, 3))
        item.clean!
        item.body = "body"
        item.dirty_list.try(&.<<(4_i64))
        item.dirty.should eq(["body", "dirty_list"])
      end

      it "correctly unmarks attributes as dirty when rolling back from copy" do
        item = DirtyTrackingSpec::MutationModel.new(mykey: "1", dirty_list: list(1, 2, 3))
        item.clean!
        item.attribute_dirty!(:dirty_list)
        item.dirty.should eq(["dirty_list"])
        item.dirty_list.try(&.<<(4_i64))
        item.dirty.should eq(["dirty_list"])
        item.rollback_attribute!(:dirty_list)
        item.dirty?.should be_false
      end

      it "correctly handles #clean! with a mutated list" do
        item = DirtyTrackingSpec::MutationModel.new(mykey: "1", body: "b", dirty_list: list(1, 2, 3))
        item.clean!
        item.dirty_list.try(&.<<(4_i64))
        item.dirty?.should be_true
        item.clean!
        item.dirty?.should be_false
        item.attribute_was(:dirty_list).should eq(list(1, 2, 3, 4))
      end

      it "correctly handles nested mutated lists" do
        # Assigning a collection that is not already a `Value` converts it, so the nested lists are
        # built as `Value`s to keep the references the Ruby example mutates. See docs/DIFFERENCES.md.
        first = list(1)
        second = list(1, 2)
        third = list(1, 2, 3)
        nested = [first.as(Aws::DynamoDB::Value), second.as(Aws::DynamoDB::Value),
                  third.as(Aws::DynamoDB::Value)] of Aws::DynamoDB::Value

        item = DirtyTrackingSpec::MutationModel.new(mykey: "1", dirty_list: nested)
        item.clean!
        item.dirty?.should be_false
        first << 2_i64
        second << 3_i64
        third << 4_i64

        item.dirty_list.should eq([list(1, 2), list(1, 2, 3), list(1, 2, 3, 4)] of Aws::DynamoDB::Value)
        item.dirty_list_was.should eq([list(1), list(1, 2), list(1, 2, 3)] of Aws::DynamoDB::Value)
        item.dirty?.should be_true
        item.rollback_attribute!(:dirty_list)
        item.dirty_list.should eq([list(1), list(1, 2), list(1, 2, 3)] of Aws::DynamoDB::Value)
      end

      it "correctly handles list equality through assignment" do
        item = DirtyTrackingSpec::MutationModel.new(mykey: "1", dirty_list: list(1, 2, 3))
        item.clean!
        item.dirty_list.try(&.<<(4_i64))
        item.dirty?.should be_true
        item.dirty_list = list(1, 2, 3)
        item.dirty?.should be_false
      end
    end

    describe "Maps" do
      map = -> { Aws::DynamoDB::Item{"a" => 1_i64, "b" => "2"} }

      it "marks mutated maps as dirty" do
        item = DirtyTrackingSpec::MutationModel.new(mykey: "1", dirty_map: map.call)
        item.clean!
        item.dirty_map.try { |value| value["c"] = 3.0 }
        item.dirty_map.should eq(Aws::DynamoDB::Item{"a" => 1_i64, "b" => "2", "c" => 3.0})
        item.dirty?.should be_true
        item.attribute_dirty?(:dirty_map).should be_true
      end

      it "has a copy of the mutated map to reference and can roll back" do
        item = DirtyTrackingSpec::MutationModel.new(mykey: "1", dirty_map: map.call)
        item.clean!
        item.dirty_map.try { |value| value["c"] = 3.0 }
        item.dirty_map_was.should eq(map.call)
        item.rollback!(:dirty_map)
        item.dirty_map.should eq(map.call)
      end

      it "includes the mutated map in the list of dirty attributes" do
        item = DirtyTrackingSpec::MutationModel.new(mykey: "1", body: "b", dirty_map: map.call)
        item.clean!
        item.body = "body"
        item.dirty_map.try { |value| value["c"] = 3.0 }
        item.dirty.should eq(["body", "dirty_map"])
      end

      it "correctly unmarks attributes as dirty when rolling back from copy" do
        item = DirtyTrackingSpec::MutationModel.new(mykey: "1", dirty_map: map.call)
        item.clean!
        item.attribute_dirty!(:dirty_map)
        item.dirty.should eq(["dirty_map"])
        item.dirty_map.try { |value| value["c"] = 3.0 }
        item.dirty.should eq(["dirty_map"])
        item.rollback_attribute!(:dirty_map)
        item.dirty?.should be_false
      end

      it "correctly handles #clean! with a mutated map" do
        item = DirtyTrackingSpec::MutationModel.new(mykey: "1", dirty_map: map.call)
        item.clean!
        item.dirty_map.try { |value| value["c"] = 3.0 }
        item.dirty?.should be_true
        item.clean!
        item.dirty?.should be_false
        item.attribute_was(:dirty_map)
          .should eq(Aws::DynamoDB::Item{"a" => 1_i64, "b" => "2", "c" => 3.0})
      end

      it "correctly handles nested mutated maps" do
        inner = Aws::DynamoDB::Item{"one" => 1_i64, "two" => 2.0}
        nested = Aws::DynamoDB::Item{"a" => inner, "b" => 2_i64}

        item = DirtyTrackingSpec::MutationModel.new(mykey: "1", dirty_map: nested)
        item.clean!
        item.dirty?.should be_false
        inner["three"] = "3"
        nested["c"] = Aws::DynamoDB::Item{"nesting" => true}

        item.dirty_map.should eq(
          Aws::DynamoDB::Item{
            "a" => Aws::DynamoDB::Item{"one" => 1_i64, "two" => 2.0, "three" => "3"},
            "b" => 2_i64,
            "c" => Aws::DynamoDB::Item{"nesting" => true},
          }
        )
        item.dirty_map_was.should eq(
          Aws::DynamoDB::Item{"a" => Aws::DynamoDB::Item{"one" => 1_i64, "two" => 2.0}, "b" => 2_i64}
        )
        item.dirty?.should be_true
        item.rollback_attribute!(:dirty_map)
        item.dirty_map.should eq(
          Aws::DynamoDB::Item{"a" => Aws::DynamoDB::Item{"one" => 1_i64, "two" => 2.0}, "b" => 2_i64}
        )
      end

      it "correctly handles map equality through assignment" do
        item = DirtyTrackingSpec::MutationModel.new(mykey: "1", dirty_map: map.call)
        item.clean!
        item.dirty_map.try { |value| value["c"] = 3.0 }
        item.dirty?.should be_true
        item.dirty_map = map.call
        item.dirty?.should be_false
      end
    end

    describe "Sets" do
      it "marks mutated sets as dirty" do
        item = DirtyTrackingSpec::MutationModel.new(mykey: "1", dirty_set: Set{"a", "b", "c"})
        item.clean!
        item.dirty_set.add("d")
        item.dirty_set.should eq(Set{"a", "b", "c", "d"})
        item.dirty?.should be_true
        item.attribute_dirty?(:dirty_set).should be_true
      end

      it "has a copy of the mutated set to reference and can roll back" do
        item = DirtyTrackingSpec::MutationModel.new(mykey: "1", dirty_set: Set{"a", "b", "c"})
        item.clean!
        item.dirty_set.add("d")
        item.dirty_set_was.should eq(Set{"a", "b", "c"})
        item.rollback!(:dirty_set)
        item.dirty_set.should eq(Set{"a", "b", "c"})
      end

      it "includes the mutated set in the list of dirty attributes" do
        item = DirtyTrackingSpec::MutationModel.new(mykey: "1", body: "b", dirty_set: Set{"a", "b", "c"})
        item.clean!
        item.body = "body"
        item.dirty_set.add("d")
        item.dirty.should eq(["body", "dirty_set"])
      end

      it "correctly unmarks attributes as dirty when rolling back from copy" do
        item = DirtyTrackingSpec::MutationModel.new(mykey: "1", dirty_set: Set{"a", "b", "c"})
        item.clean!
        item.attribute_dirty!(:dirty_set)
        item.dirty.should eq(["dirty_set"])
        item.dirty_set.add("d")
        item.dirty.should eq(["dirty_set"])
        item.rollback_attribute!(:dirty_set)
        item.dirty?.should be_false
      end

      it "correctly handles #clean! with a mutated set" do
        item = DirtyTrackingSpec::MutationModel.new(mykey: "1", dirty_set: Set{"a", "b", "c"})
        item.clean!
        item.dirty_set.add("d")
        item.dirty?.should be_true
        item.clean!
        item.dirty?.should be_false
        item.attribute_was(:dirty_set).should eq(Set{"a", "b", "c", "d"})
      end

      it "correctly handles set equality through assignment" do
        item = DirtyTrackingSpec::MutationModel.new(mykey: "1", dirty_set: Set{"a", "b", "c"})
        item.clean!
        item.dirty_set.add("d")
        item.dirty?.should be_true
        item.dirty_set = Set{"a", "b", "c"}
        item.dirty?.should be_false
      end
    end
  end
end

# Parity: 52/52 examples from spec/aws-record/record/dirty_tracking_spec.rb (aws-record 2.15.1)
