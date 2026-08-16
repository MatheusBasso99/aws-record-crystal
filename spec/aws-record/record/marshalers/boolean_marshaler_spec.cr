require "../../../spec_helper"

describe Aws::Record::Marshalers::BooleanMarshaler do
  describe "default settings" do
    marshaler = Aws::Record::Marshalers::BooleanMarshaler.new

    describe "type casting" do
      it "type casts nil and empty strings as nil" do
        marshaler.type_cast(nil).should be_nil
        marshaler.type_cast("").should be_nil
      end

      it "type casts false equivalents as false" do
        marshaler.type_cast("false").should be_false
        marshaler.type_cast("0").should be_false
        marshaler.type_cast(0_i64).should be_false
      end
    end

    describe "serialization for storage" do
      it "stores booleans as themselves" do
        marshaler.serialize(true).should be_true
      end

      it "attempts to type cast before storage" do
        marshaler.serialize(0_i64).should be_false
      end

      it "identifies nil objects as the NULL type" do
        marshaler.serialize(nil).should be_nil
      end
    end
  end

  describe "the remaining RawValue shapes" do
    marshaler = Aws::Record::Marshalers::BooleanMarshaler.new

    it "casts a non-zero number as true" do
      marshaler.type_cast(1_i64).should be_true
      marshaler.type_cast(0.5).should be_true
      marshaler.type_cast(BigDecimal.new(0)).should be_false
    end

    it "casts anything else as true" do
      marshaler.type_cast("yes").should be_true
      marshaler.type_cast(Set{"a"}).should be_true
    end
  end
end

# Parity: 5/5 examples from spec/aws-record/record/marshalers/boolean_marshaler_spec.rb (aws-record 2.15.1)
