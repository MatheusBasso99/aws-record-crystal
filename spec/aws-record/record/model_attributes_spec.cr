require "../../spec_helper"

# `ModelAttributes` is built by the attribute macros, which catch these collisions at compile time
# (see `spec/fixtures/compile_errors`). It keeps the runtime checks the Ruby gem has, for models
# that register attributes themselves, and they are asserted here.
private def attribute(name : String, storage : String? = nil) : Aws::Record::Attribute
  Aws::Record::Attribute.new(name, database_attribute_name: storage)
end

describe Aws::Record::ModelAttributes do
  describe "#register_attribute" do
    it "keeps attributes in declaration order" do
      attributes = Aws::Record::ModelAttributes.new
      attributes.register_attribute(attribute("b"))
      attributes.register_attribute(attribute("a"))
      attributes.attributes.keys.should eq(["b", "a"])
    end

    it "returns the attribute it registered" do
      attributes = Aws::Record::ModelAttributes.new
      registered = attribute("a")
      attributes.register_attribute(registered).should be(registered)
    end

    it "refuses to overwrite an existing attribute" do
      attributes = Aws::Record::ModelAttributes.new
      attributes.register_attribute(attribute("a"))
      expect_raises(Aws::Record::Errors::NameCollision, "Cannot overwrite existing attribute a") do
        attributes.register_attribute(attribute("a"))
      end
    end

    it "refuses a storage name that is already an attribute name" do
      attributes = Aws::Record::ModelAttributes.new
      attributes.register_attribute(attribute("a"))
      expect_raises(Aws::Record::Errors::NameCollision, "already exists as an attribute name") do
        attributes.register_attribute(attribute("b", storage: "a"))
      end
    end

    it "refuses an attribute name that is already a storage name" do
      attributes = Aws::Record::ModelAttributes.new
      attributes.register_attribute(attribute("a", storage: "column"))
      expect_raises(Aws::Record::Errors::NameCollision, "already exists as a custom storage name") do
        attributes.register_attribute(attribute("column", storage: "other"))
      end
    end

    it "refuses a storage name that is already in use" do
      attributes = Aws::Record::ModelAttributes.new
      attributes.register_attribute(attribute("a", storage: "shared"))
      expect_raises(Aws::Record::Errors::NameCollision, "already in use") do
        attributes.register_attribute(attribute("b", storage: "shared"))
      end
    end
  end

  describe "lookups" do
    it "finds attributes by name and by symbol" do
      attributes = Aws::Record::ModelAttributes.new
      registered = attributes.register_attribute(attribute("a", storage: "column_a"))
      attributes.attribute_for("a").should be(registered)
      attributes.attribute_for(:a).should be(registered)
      attributes.attribute_for("missing").should be_nil
    end

    it "maps names to storage names and back" do
      attributes = Aws::Record::ModelAttributes.new
      attributes.register_attribute(attribute("a", storage: "column_a"))
      attributes.storage_name_for("a").should eq("column_a")
      attributes.db_to_attribute_name("column_a").should eq("a")
      attributes.db_to_attribute_name("nope").should be_nil
    end

    it "raises when asked for the storage name of an unknown attribute" do
      expect_raises(KeyError, "No such attribute nope") do
        Aws::Record::ModelAttributes.new.storage_name_for("nope")
      end
    end

    it "answers whether an attribute is present" do
      attributes = Aws::Record::ModelAttributes.new
      attributes.register_attribute(attribute("a"))
      attributes.present?("a").should be_true
      attributes.present?(:a).should be_true
      attributes.present?("b").should be_false
    end
  end
end

describe Aws::Record::KeyAttributes do
  it "starts with no keys" do
    attributes = Aws::Record::ModelAttributes.new
    keys = Aws::Record::KeyAttributes.new(attributes)
    keys.hash_key.should be_nil
    keys.range_key.should be_nil
    keys.hash_key_attribute.should be_nil
    keys.range_key_attribute.should be_nil
    keys.keys.should be_empty
  end

  it "resolves the attributes of the keys it was given" do
    attributes = Aws::Record::ModelAttributes.new
    hash_attribute = attributes.register_attribute(attribute("id"))
    range_attribute = attributes.register_attribute(attribute("date"))
    keys = Aws::Record::KeyAttributes.new(attributes)
    keys.hash_key = "id"
    keys.range_key = "date"

    keys.hash_key.should eq("id")
    keys.range_key.should eq("date")
    keys.hash_key_attribute.should be(hash_attribute)
    keys.range_key_attribute.should be(range_attribute)
    keys.keys.should eq({:hash => "id", :range => "date"})
  end
end

describe Aws::Record::ModelDefinition do
  it "builds an empty definition" do
    definition = Aws::Record::ModelDefinition.empty
    definition.attributes.attributes.should be_empty
    definition.keys.hash_key.should be_nil
  end
end
