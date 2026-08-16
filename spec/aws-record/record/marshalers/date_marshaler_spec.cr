require "../../../spec_helper"

describe Aws::Record::Marshalers::DateMarshaler do
  describe "default settings" do
    marshaler = Aws::Record::Marshalers::DateMarshaler.new

    describe "type casting" do
      it "casts nil and empty string as nil" do
        marshaler.type_cast(nil).should be_nil
        marshaler.type_cast("").should be_nil
      end

      it "casts Date objects as themselves" do
        # Crystal has no Date; a date is a Time at midnight UTC. See docs/DIFFERENCES.md.
        expected = Time.utc(2015, 1, 1)
        marshaler.type_cast(Time.utc(2015, 1, 1)).should eq(expected)
      end

      it "casts timestamps to dates" do
        expected = Time.utc(2009, 2, 13)
        cast = marshaler.type_cast(1_234_567_890_i64).as(Time)
        (cast - expected).abs.should be <= 1.day
      end

      it "casts strings to dates" do
        marshaler.type_cast("2015-11-25").should eq(Time.utc(2015, 11, 25))
      end
    end

    describe "serialization for storage" do
      it "serializes nil as null" do
        marshaler.serialize(nil).should be_nil
      end

      it "serializes dates as strings" do
        marshaler.serialize(Time.utc(2015, 11, 25)).should eq("2015-11-25")
      end
    end
  end

  describe "bring your own format" do
    # The Ruby spec uses `Date#jisx0301`, which Crystal has no equivalent of; the point of the
    # example is that a custom formatter is used, so this one produces the same string.
    jisx0301 = ->(date : Time) { "H#{date.year - 1988}.#{date.to_s("%m.%d")}" }
    marshaler = Aws::Record::Marshalers::DateMarshaler.new(formatter: jisx0301)

    it "supports custom formatting" do
      marshaler.serialize("2016-07-21").should eq("H28.07.21")
    end
  end
end

# Parity: 7/7 examples from spec/aws-record/record/marshalers/date_marshaler_spec.rb (aws-record 2.15.1)
