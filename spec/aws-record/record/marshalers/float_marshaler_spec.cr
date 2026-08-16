require "../../../spec_helper"

describe Aws::Record::Marshalers::FloatMarshaler do
  describe "default settings" do
    marshaler = Aws::Record::Marshalers::FloatMarshaler.new

    describe "type casting" do
      it "casts nil and empty strings as nil" do
        marshaler.type_cast(nil).should be_nil
        marshaler.type_cast("").should be_nil
      end

      it "casts stringy floats to a float" do
        marshaler.type_cast("5.5").should eq(5.5)
      end

      it "passes through float values" do
        marshaler.type_cast(1.2).should eq(1.2)
      end

      it "handles classes which do not directly serialize to floats" do
        marshaler.type_cast("5").should eq(5.0)
        marshaler.type_cast(5_i64).should eq(5.0)
        marshaler.type_cast(BigDecimal.new("5")).should eq(5.0)
      end
    end

    describe "serialization for storage" do
      it "serializes nil as null" do
        marshaler.serialize(nil).should be_nil
      end

      it "serializes floats with the numeric type" do
        marshaler.serialize(3.0).should eq(3.0)
      end

      it "raises when type_cast does not do what it is expected to do" do
        # In Crystal this cannot happen: `#type_cast` is typed to return `Float64?`. Values Ruby
        # would have turned into a non-float become zero, as `"wrong".to_f` does there.
        marshaler.serialize("wrong").should eq(0.0)
        marshaler.serialize(Set{"a"}).should eq(0.0)
      end
    end
  end
end

# Parity: 7/7 examples from spec/aws-record/record/marshalers/float_marshaler_spec.rb (aws-record 2.15.1)
