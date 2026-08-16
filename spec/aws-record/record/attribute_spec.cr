require "../../spec_helper"

describe Aws::Record::Attribute do
  describe "database_attribute_name" do
    it "can have a custom DB name" do
      attribute = Aws::Record::Attribute.new(:foo, database_attribute_name: "bar")
      # Attribute names are `String` here; Crystal cannot create symbols at runtime.
      attribute.name.should eq("foo")
      attribute.database_name.should eq("bar")
    end

    it "can accept a symbol as a custom DB name" do
      attribute = Aws::Record::Attribute.new(:foo, database_attribute_name: :bar)
      attribute.name.should eq("foo")
      attribute.database_name.should eq("bar")
    end

    it "uses the attribute name by default for the DB name" do
      attribute = Aws::Record::Attribute.new(:foo)
      attribute.name.should eq("foo")
      attribute.database_name.should eq("foo")
    end
  end

  describe "default_value" do
    it "supports lambdas" do
      attribute = Aws::Record::Attribute.new(:foo, default_value_proc: Aws::Record::Attribute.default_proc { 2 + 3 })
      attribute.default_value.should eq(5_i64)
    end

    it "does not type_cast lambdas" do
      calls = 0
      proc = Aws::Record::Attribute.default_proc do
        calls += 1
        Time.utc
      end
      attribute = Aws::Record::Attribute.new(
        :foo, marshaler: Aws::Record::Marshalers::DateTimeMarshaler.new, default_value_proc: proc
      )
      calls.should eq(0)
      attribute.default_value
      calls.should eq(1)
    end

    it "type casts result of calling a default_value lambda" do
      attribute = Aws::Record::Attribute.new(
        :foo,
        marshaler: Aws::Record::Marshalers::StringMarshaler.new,
        default_value_proc: Aws::Record::Attribute.default_proc { :huzzah }
      )
      attribute.default_value.should be_a(String)
    end

    it "uses a deep copy" do
      attribute = Aws::Record::Attribute.new(
        :foo, default_value: Aws::DynamoDB::Item.new, default_value_set: true
      )
      attribute.default_value.as(Aws::DynamoDB::Item)["greeting"] = "hi"
      attribute.default_value.should eq(Aws::DynamoDB::Item.new)
    end

    it "does not type_cast unset value" do
      attribute = Aws::Record::Attribute.new(:foo, marshaler: Aws::Record::Marshalers::StringSetMarshaler.new)
      attribute.default_value.should be_nil
      attribute.default_value?.should be_false
    end

    it "type casts nil value" do
      attribute = Aws::Record::Attribute.new(
        :foo,
        marshaler: Aws::Record::Marshalers::StringSetMarshaler.new,
        default_value: nil,
        default_value_set: true
      )
      attribute.default_value.should be_a(Set(String))
      attribute.default_value?.should be_true
    end
  end

  describe "#type_cast" do
    it "falls back to the default value when the cast is nil" do
      attribute = Aws::Record::Attribute.new(
        :foo,
        marshaler: Aws::Record::Marshalers::StringMarshaler.new,
        default_value: "fallback",
        default_value_set: true
      )
      attribute.type_cast(nil).should eq("fallback")
      attribute.type_cast("given").should eq("given")
    end
  end

  describe "#serialize" do
    it "serializes through the marshaler" do
      attribute = Aws::Record::Attribute.new(:foo, marshaler: Aws::Record::Marshalers::IntegerMarshaler.new)
      attribute.serialize("5").should eq(5_i64)
      attribute.serialize(nil).should be_nil
    end
  end

  describe "#extract" do
    it "reads the value stored under its database name" do
      attribute = Aws::Record::Attribute.new(:foo, database_attribute_name: "bar")
      attribute.extract(Aws::DynamoDB::Item{"bar" => 1_i64}).should eq(1_i64)
    end

    it "returns nil when the item has no such attribute" do
      Aws::Record::Attribute.new(:foo).extract(Aws::DynamoDB::Item.new).should be_nil
    end
  end

  describe "#persist_nil?" do
    it "is false unless asked for" do
      Aws::Record::Attribute.new(:foo).persist_nil?.should be_false
      Aws::Record::Attribute.new(:foo, persist_nil: true).persist_nil?.should be_true
    end
  end

  describe "#dynamodb_type" do
    it "carries the scalar type of the attribute" do
      Aws::Record::Attribute.new(:foo, dynamodb_type: "S").dynamodb_type.should eq("S")
      Aws::Record::Attribute.new(:foo).dynamodb_type.should be_nil
    end
  end

  describe "the default marshaler" do
    it "passes values through" do
      attribute = Aws::Record::Attribute.new(:foo)
      attribute.type_cast("anything").should eq("anything")
      attribute.serialize(Set{"a"}).should eq(Set{"a"})
    end

    it "refuses to serialize a Time, which DynamoDB has no type for" do
      attribute = Aws::Record::Attribute.new(:foo)
      expect_raises(ArgumentError, "DefaultMarshaler cannot serialize a Time") do
        attribute.serialize(Time.utc(2015, 11, 25))
      end
    end
  end
end

# Parity: 9/9 examples from spec/aws-record/record/attribute_spec.rb (aws-record 2.15.1), plus extras
