require "../../../spec_helper"

describe Aws::Record::Marshalers::StringMarshaler do
  describe "default settings" do
    marshaler = Aws::Record::Marshalers::StringMarshaler.new

    describe "type casting" do
      it "type casts nil as nil" do
        marshaler.type_cast(nil).should be_nil
      end

      it "type casts an empty string as an empty string" do
        marshaler.type_cast("").should eq("")
      end

      it "type casts a string as a string" do
        marshaler.type_cast("Hello").should eq("Hello")
      end

      it "type casts other types as a string" do
        marshaler.type_cast(5_i64).should eq("5")
      end
    end

    describe "serialization for storage" do
      it "stores strings as themselves" do
        marshaler.serialize("Hello").should eq("Hello")
      end

      it "attempts to type cast before storage" do
        marshaler.serialize(5_i64).should eq("5")
      end

      it "identifies nil objects as the NULL type" do
        marshaler.serialize(nil).should be_nil
      end

      it "always serializes empty strings as NULL" do
        marshaler.serialize("").should be_nil
      end

      it "raises if #type_cast failed to create a string" do
        # In Crystal this cannot happen: `#type_cast` is typed to return `String?`, so every
        # `RawValue` shape serializes to a `String` or to nil. See docs/DIFFERENCES.md.
        values = [true, 1_i64, 1.5, BigDecimal.new(1), "bytes".to_slice, Set{"a"},
                  [1_i64] of Aws::DynamoDB::Value, Aws::DynamoDB::Item{"a" => 1_i64},
                  Time.utc(2015, 11, 25)] of Aws::Record::RawValue
        values.each { |value| marshaler.serialize(value).should be_a(String) }
      end
    end
  end
end

# Parity: 9/9 examples from spec/aws-record/record/marshalers/string_marshaler_spec.rb (aws-record 2.15.1)
