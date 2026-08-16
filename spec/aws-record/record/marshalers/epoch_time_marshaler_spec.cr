require "../../../spec_helper"

describe Aws::Record::Marshalers::EpochTimeMarshaler do
  describe "default settings" do
    marshaler = Aws::Record::Marshalers::EpochTimeMarshaler.new

    describe "type casting" do
      it "casts nil and empty string as nil" do
        marshaler.type_cast(nil).should be_nil
        marshaler.type_cast("").should be_nil
      end

      it "passes through Time objects" do
        marshaler.type_cast(Time.unix(1_531_173_732)).should eq(Time.unix(1_531_173_732))
      end

      it "converts timestamps to Time" do
        marshaler.type_cast(1_531_173_732_i64).should eq(Time.unix(1_531_173_732))
      end

      it "converts BigDecimal objects to Time" do
        marshaler.type_cast(BigDecimal.new(1_531_173_732)).should eq(Time.unix(1_531_173_732))
      end

      it "converts DateTimes to Time" do
        marshaler.type_cast(Time.utc(2009, 2, 13, 23, 31, 30)).should eq(Time.utc(2009, 2, 13, 23, 31, 30))
      end

      it "converts strings to Time" do
        marshaler.type_cast("2009-02-13 23:31:30 UTC").should eq(Time.utc(2009, 2, 13, 23, 31, 30))
      end

      it "converts automatically to utc" do
        cast = marshaler.type_cast("2016-07-20 16:31:10 -0700").as(Time)
        cast.should eq(Time.utc(2016, 7, 20, 23, 31, 10))
        cast.utc?.should be_true
      end

      it "raises when unable to parse as a Time" do
        expect_raises(ArgumentError) { marshaler.type_cast("that time when") }
      end
    end

    describe "serialization for storage" do
      it "serializes nil as null" do
        marshaler.serialize(nil).should be_nil
      end

      it "serializes Time in epoch seconds" do
        marshaler.serialize(Time.utc(2018, 7, 9, 22, 2, 12)).should eq(1_531_173_732_i64)
      end
    end
  end

  describe "use local time" do
    marshaler = Aws::Record::Marshalers::EpochTimeMarshaler.new(use_local_time: true)

    it "does not automatically convert to utc" do
      expected = Time.parse!("2016-07-20 16:31:10 -0700", "%F %T %z")
      cast = marshaler.type_cast("2016-07-20 16:31:10 -0700").as(Time)
      cast.should eq(expected)
      cast.utc?.should be_false
    end
  end
end

# Parity: 11/11 examples from spec/aws-record/record/marshalers/epoch_time_marshaler_spec.rb (aws-record 2.15.1)
