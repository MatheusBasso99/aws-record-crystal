require "../../../spec_helper"

describe Aws::Record::Marshalers::StringSetMarshaler do
  describe "default settings" do
    marshaler = Aws::Record::Marshalers::StringSetMarshaler.new

    describe "#type_cast" do
      it "type casts nil as an empty set" do
        marshaler.type_cast(nil).should eq(Set(String).new)
      end

      it "type casts an empty string as an empty set" do
        marshaler.type_cast("").should eq(Set(String).new)
      end

      it "type casts string sets as themselves" do
        marshaler.type_cast(Set{"1", "2", "3"}).should eq(Set{"1", "2", "3"})
      end

      it "type casts arrays to sets for you" do
        input = ["1", "2", "3", "2"] of Aws::DynamoDB::Value
        marshaler.type_cast(input).should eq(Set{"1", "2", "3"})
      end

      it "attempts to stringify all contents of a set" do
        # A Crystal `Set` is homogeneous, so a mixed collection arrives as a list.
        input = [1_i64, "2", 3_i64] of Aws::DynamoDB::Value
        marshaler.type_cast(input).should eq(Set{"1", "2", "3"})
        marshaler.type_cast(Set{BigDecimal.new(1)}).should eq(Set{"1.0"})
      end

      it "raises when it does not know how to typecast to a set" do
        expect_raises(ArgumentError, "into a String Set!") { marshaler.type_cast("fail") }
      end
    end

    describe "#serialize" do
      it "serializes an empty set as nil" do
        marshaler.serialize(Set(String).new).should be_nil
      end

      it "serializes string sets as themselves" do
        marshaler.serialize(Set{"1", "2", "3"}).should eq(Set{"1", "2", "3"})
      end
    end
  end
end

# Parity: 8/8 examples from spec/aws-record/record/marshalers/string_set_marshaler_spec.rb (aws-record 2.15.1)
