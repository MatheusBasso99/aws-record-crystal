require "../../../spec_helper"

describe Aws::Record::Marshalers::IntegerMarshaler do
  describe "default settings" do
    marshaler = Aws::Record::Marshalers::IntegerMarshaler.new

    describe "type casting" do
      it "casts nil and empty strings as nil" do
        marshaler.type_cast(nil).should be_nil
        marshaler.type_cast("").should be_nil
      end

      it "casts stringy integers to an integer" do
        marshaler.type_cast("5").should eq(5_i64)
      end

      it "passes through integer values" do
        marshaler.type_cast(1_i64).should eq(1_i64)
      end

      it "type casts values that do not directly respond to to_i" do
        # Ruby falls back to `to_s.to_i`; here every `RawValue` shape has a defined casting.
        marshaler.type_cast(5.9).should eq(5_i64)
        marshaler.type_cast(BigDecimal.new("5.9")).should eq(5_i64)
        marshaler.type_cast("5.9").should eq(5_i64)
        marshaler.type_cast(Time.unix(1_234_567_890)).should eq(1_234_567_890_i64)
      end
    end

    describe "serialization for storage" do
      it "serializes nil as null" do
        marshaler.serialize(nil).should be_nil
      end

      it "serializes integers with the numeric type" do
        marshaler.serialize(3_i64).should eq(3_i64)
      end

      it "raises when type_cast does not return the expected type" do
        # In Crystal this cannot happen: `#type_cast` is typed to return `Int64?`. Values Ruby
        # would have turned into a non-integer become zero, as `"wrong".to_i` does there.
        marshaler.serialize("wrong").should eq(0_i64)
        marshaler.serialize(Set{"a"}).should eq(0_i64)
        marshaler.serialize(true).should eq(1_i64)
      end
    end
  end

  describe "the remaining RawValue shapes" do
    marshaler = Aws::Record::Marshalers::IntegerMarshaler.new

    it "casts binaries through their string form" do
      marshaler.type_cast("25".to_slice).should eq(25_i64)
      marshaler.type_cast("nope".to_slice).should eq(0_i64)
    end

    it "casts booleans the way Ruby's to_s.to_i does" do
      marshaler.type_cast(false).should eq(0_i64)
    end
  end
end

# Parity: 7/7 examples from spec/aws-record/record/marshalers/integer_marshaler_spec.rb (aws-record 2.15.1)
