require "../../../spec_helper"

describe Aws::Record::Marshalers::ListMarshaler do
  describe "default settings" do
    marshaler = Aws::Record::Marshalers::ListMarshaler.new

    describe "type casting" do
      it "type casts nil as nil" do
        marshaler.type_cast(nil).should be_nil
      end

      it "type casts an empty string as nil" do
        marshaler.type_cast("").should be_nil
      end

      it "type casts Arrays as themselves" do
        list = [1_i64, "Two", 3_i64] of Aws::DynamoDB::Value
        marshaler.type_cast(list).should eq(list)
      end

      it "type casts enumerables as an Array" do
        input = Aws::DynamoDB::Item{"a" => 1_i64, "b" => 2_i64, "c" => 3_i64}
        expected = [
          ["a", 1_i64] of Aws::DynamoDB::Value,
          ["b", 2_i64] of Aws::DynamoDB::Value,
          ["c", 3_i64] of Aws::DynamoDB::Value,
        ] of Aws::DynamoDB::Value
        marshaler.type_cast(input).should eq(expected)
      end

      it "raises if it cannot type cast to an Array" do
        expect_raises(ArgumentError, "into an array!") { marshaler.type_cast(5_i64) }
      end
    end

    describe "serialization" do
      it "serializes an array as itself" do
        list = [1_i64, 2_i64, 3_i64] of Aws::DynamoDB::Value
        marshaler.serialize(list).should eq(list)
      end

      it "serializes nil as nil" do
        marshaler.serialize(nil).should be_nil
      end
    end
  end
end

# Parity: 7/7 examples from spec/aws-record/record/marshalers/list_marshaler_spec.rb (aws-record 2.15.1)
