require "../../../spec_helper"

describe Aws::Record::Marshalers::MapMarshaler do
  describe "default settings" do
    marshaler = Aws::Record::Marshalers::MapMarshaler.new

    describe "type casting" do
      it "type casts nil as nil" do
        marshaler.type_cast(nil).should be_nil
      end

      it "type casts an empty string as nil" do
        marshaler.type_cast("").should be_nil
      end

      it "type casts Hashes as themselves" do
        input = Aws::DynamoDB::Item{"a" => 1_i64, "b" => "Two", "c" => 3.0}
        marshaler.type_cast(input).should eq(input)
      end

      it "type casts classes which respond to :to_h as a Hash" do
        # Crystal has no `to_h` duck type over `RawValue`; a list of pairs is the shape a map can
        # still be recovered from, mirroring Ruby's `Array#to_h`. See docs/DIFFERENCES.md.
        input = [
          ["a", 1_i64] of Aws::DynamoDB::Value,
          ["b", "Two"] of Aws::DynamoDB::Value,
          ["c", 3.0] of Aws::DynamoDB::Value,
        ] of Aws::DynamoDB::Value
        expected = Aws::DynamoDB::Item{"a" => 1_i64, "b" => "Two", "c" => 3.0}
        marshaler.type_cast(input).should eq(expected)
      end

      it "raises if it cannot type cast to a Hash" do
        expect_raises(ArgumentError, "into a hash!") { marshaler.type_cast(5_i64) }
        expect_raises(ArgumentError, "into a hash!") { marshaler.type_cast([1_i64] of Aws::DynamoDB::Value) }
      end
    end

    describe "serialization" do
      it "serializes a map as itself" do
        input = Aws::DynamoDB::Item{"a" => 1_i64, "b" => "Two", "c" => 3.0}
        marshaler.serialize(input).should eq(input)
      end

      it "serializes nil as nil" do
        marshaler.serialize(nil).should be_nil
      end
    end
  end

  describe "pairs that are not pairs" do
    marshaler = Aws::Record::Marshalers::MapMarshaler.new

    it "raises when a list element is not a two element pair" do
      pairs = [["a", 1_i64, 2_i64] of Aws::DynamoDB::Value] of Aws::DynamoDB::Value
      expect_raises(ArgumentError, "into a hash!") { marshaler.type_cast(pairs) }
    end

    it "stringifies a pair key that is not a string" do
      pairs = [[1_i64, "one"] of Aws::DynamoDB::Value] of Aws::DynamoDB::Value
      marshaler.type_cast(pairs).should eq(Aws::DynamoDB::Item{"1" => "one"})
    end
  end
end

# Parity: 7/7 examples from spec/aws-record/record/marshalers/map_marshaler_spec.rb (aws-record 2.15.1)
