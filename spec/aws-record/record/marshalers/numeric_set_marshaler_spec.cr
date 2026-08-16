require "../../../spec_helper"

describe Aws::Record::Marshalers::NumericSetMarshaler do
  describe "default settings" do
    marshaler = Aws::Record::Marshalers::NumericSetMarshaler.new

    describe "#type_cast" do
      it "type casts nil as an empty set" do
        marshaler.type_cast(nil).should eq(Set(BigDecimal).new)
      end

      it "type casts an empty string as an empty set" do
        marshaler.type_cast("").should eq(Set(BigDecimal).new)
      end

      it "type casts numeric sets as themselves" do
        # Numeric sets are always `Set(BigDecimal)` here, so no precision is lost on the wire.
        input = Set{BigDecimal.new(1), BigDecimal.new("2.0"), BigDecimal.new(3)}
        marshaler.type_cast(input).should eq(input)
      end

      it "type casts a list to a set on your behalf" do
        input = [1_i64, 2.0, 3_i64] of Aws::DynamoDB::Value
        expected = Set{BigDecimal.new(1), BigDecimal.new("2.0"), BigDecimal.new(3)}
        marshaler.type_cast(input).should eq(expected)
      end

      it "attempts to cast as numeric all contents of a set" do
        input = [1_i64, "2.0", "3"] of Aws::DynamoDB::Value
        expected = Set{BigDecimal.new(1), BigDecimal.new("2.0"), BigDecimal.new("3")}
        marshaler.type_cast(input).should eq(expected)
        marshaler.type_cast(Set{"4"}).should eq(Set{BigDecimal.new("4")})
      end

      it "raises when unable to type cast as a set" do
        expect_raises(ArgumentError, "into a Numeric Set!") { marshaler.type_cast("fail") }
        expect_raises(ArgumentError, "into a number!") { marshaler.type_cast([true] of Aws::DynamoDB::Value) }
      end
    end

    describe "#serialize" do
      it "serializes an empty set as nil" do
        marshaler.serialize(Set(BigDecimal).new).should be_nil
      end

      it "serializes numeric sets as themselves" do
        input = Set{BigDecimal.new(1), BigDecimal.new("2.0"), BigDecimal.new(3)}
        marshaler.serialize(input).should eq(input)
      end
    end
  end
end

# Parity: 8/8 examples from spec/aws-record/record/marshalers/numeric_set_marshaler_spec.rb (aws-record 2.15.1)
