require "../../spec_helper"

private def model_attributes(*, default : Aws::Record::RawValue = nil,
                             default_set : Bool = false, persist_nil : Bool = false) : Aws::Record::ModelAttributes
  attributes = Aws::Record::ModelAttributes.new
  attributes.register_attribute(
    Aws::Record::Attribute.new("id", marshaler: Aws::Record::Marshalers::IntegerMarshaler.new, dynamodb_type: "N")
  )
  attributes.register_attribute(
    Aws::Record::Attribute.new(
      "body",
      marshaler: Aws::Record::Marshalers::StringMarshaler.new,
      database_attribute_name: "column_body",
      persist_nil: persist_nil,
      default_value: default,
      default_value_set: default_set
    )
  )
  attributes.register_attribute(
    Aws::Record::Attribute.new("tags", marshaler: Aws::Record::Marshalers::StringSetMarshaler.new)
  )
  attributes
end

describe Aws::Record::ItemData do
  describe "#initialize" do
    it "starts as a new, undestroyed record" do
      data = Aws::Record::ItemData.new(model_attributes)
      data.new_record?.should be_true
      data.destroyed?.should be_false
      data.persisted?.should be_false
    end

    it "fills in default values" do
      data = Aws::Record::ItemData.new(model_attributes(default: "hello", default_set: true))
      data.raw_value("body").should eq("hello")
      data.raw_value("id").should be_nil
    end
  end

  describe "#get_attribute" do
    it "casts the raw value through the attribute's marshaler" do
      data = Aws::Record::ItemData.new(model_attributes)
      data.set_attribute("id", "5")
      data.get_attribute("id").should eq(5_i64)
    end

    it "returns nil for an attribute the model does not have" do
      Aws::Record::ItemData.new(model_attributes).get_attribute("nope").should be_nil
    end
  end

  describe "#build_save_hash" do
    it "keys values by storage name and serializes them" do
      data = Aws::Record::ItemData.new(model_attributes)
      data.set_attribute("id", 1_i64)
      data.set_attribute("body", "hello")
      data.build_save_hash.should eq(Aws::DynamoDB::Item{"id" => 1_i64, "column_body" => "hello"})
    end

    it "leaves out a nil value" do
      data = Aws::Record::ItemData.new(model_attributes)
      data.set_attribute("id", 1_i64)
      data.set_attribute("body", nil)
      data.build_save_hash.should eq(Aws::DynamoDB::Item{"id" => 1_i64})
    end

    it "writes a nil value when the attribute asked to persist it" do
      data = Aws::Record::ItemData.new(model_attributes(persist_nil: true))
      data.set_attribute("body", nil)
      data.build_save_hash.should eq(Aws::DynamoDB::Item{"column_body" => nil})
    end

    it "leaves out an attribute the model does not have" do
      data = Aws::Record::ItemData.new(model_attributes)
      data.set_attribute("nope", "x")
      data.build_save_hash.should be_empty
    end
  end

  describe "dirty tracking" do
    it "reports every set attribute as dirty on a new item" do
      data = Aws::Record::ItemData.new(model_attributes)
      data.set_attribute("id", 1_i64)
      data.dirty?.should be_true
      # A set attribute casts to an empty set rather than nil, so it counts as changed on a new
      # item — the same as in the Ruby gem.
      data.dirty.should eq(["id", "tags"])
    end

    it "is clean after #clean!" do
      data = Aws::Record::ItemData.new(model_attributes)
      data.set_attribute("id", 1_i64)
      data.clean!
      data.dirty?.should be_false
      data.dirty.should be_empty
      data.attribute_was("id").should eq(1_i64)
    end

    it "notices a value that changed after cleaning" do
      data = Aws::Record::ItemData.new(model_attributes)
      data.set_attribute("id", 1_i64)
      data.clean!
      data.set_attribute("id", 2_i64)
      data.attribute_dirty?("id").should be_true
      data.attribute_was("id").should eq(1_i64)
    end

    it "notices a value mutated in place" do
      data = Aws::Record::ItemData.new(model_attributes)
      data.set_attribute("tags", Set{"a"})
      data.clean!
      data.raw_value("tags").as(Set(String)) << "b"
      data.attribute_dirty?("tags").should be_true
    end

    it "does not notice a value mutated in place with mutation tracking off" do
      data = Aws::Record::ItemData.new(model_attributes, track_mutations: false)
      data.set_attribute("tags", Set{"a"})
      data.clean!
      data.raw_value("tags").as(Set(String)) << "b"
      data.attribute_dirty?("tags").should be_false
    end

    it "can be told an attribute is dirty" do
      data = Aws::Record::ItemData.new(model_attributes)
      data.clean!
      data.attribute_dirty?("id").should be_false
      data.attribute_dirty!("id")
      data.attribute_dirty?("id").should be_true
    end

    it "rolls an attribute back to its clean value" do
      data = Aws::Record::ItemData.new(model_attributes)
      data.set_attribute("id", 1_i64)
      data.clean!
      data.set_attribute("id", 2_i64)
      data.rollback_attribute!("id").should eq(1_i64)
      data.attribute_dirty?("id").should be_false
    end

    it "leaves a clean attribute alone when rolling back" do
      data = Aws::Record::ItemData.new(model_attributes)
      data.set_attribute("id", 1_i64)
      data.clean!
      data.rollback_attribute!("id").should eq(1_i64)
    end
  end

  describe "#hash_copy" do
    it "returns a copy of the raw values" do
      data = Aws::Record::ItemData.new(model_attributes)
      data.set_attribute("id", 1_i64)
      copy = data.hash_copy
      copy["id"] = 99_i64
      data.raw_value("id").should eq(1)
    end
  end

  describe "record state" do
    it "is persisted once it is neither new nor destroyed" do
      data = Aws::Record::ItemData.new(model_attributes)
      data.new_record = false
      data.persisted?.should be_true
      data.destroyed = true
      data.persisted?.should be_false
    end
  end
end
