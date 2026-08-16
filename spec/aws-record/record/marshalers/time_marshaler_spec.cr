require "../../../spec_helper"

describe Aws::Record::Marshalers::TimeMarshaler do
  describe "default settings" do
    marshaler = Aws::Record::Marshalers::TimeMarshaler.new

    describe "type casting" do
      it "casts nil and empty string as nil" do
        marshaler.type_cast(nil).should be_nil
        marshaler.type_cast("").should be_nil
      end

      it "passes through Time objects" do
        expected = Time.parse!("2015-11-15 17:12:56 +0700", "%F %T %z")
        marshaler.type_cast(Time.parse!("2015-11-15 17:12:56 +0700", "%F %T %z")).should eq(expected)
      end

      it "converts timestamps to Time" do
        marshaler.type_cast(1_234_567_890_i64).should eq(Time.utc(2009, 2, 13, 23, 31, 30))
      end

      it "converts DateTimes to Time" do
        # Crystal has one time type, so this is the same value in both spellings.
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

      it "serializes Time as a string" do
        marshaler.serialize(Time.utc(2009, 2, 13, 23, 31, 30)).should eq("2009-02-13T23:31:30Z")
      end
    end
  end

  describe "use local time" do
    marshaler = Aws::Record::Marshalers::TimeMarshaler.new(use_local_time: true)

    it "does not automatically convert to utc" do
      expected = Time.parse!("2016-07-20 16:31:10 -0700", "%F %T %z")
      cast = marshaler.type_cast("2016-07-20 16:31:10 -0700").as(Time)
      cast.should eq(expected)
      cast.utc?.should be_false
    end

    it "serializes a local time with its numeric offset" do
      marshaler.serialize("2015-11-15 17:12:56 +0700").should eq("2015-11-15T17:12:56+07:00")
    end
  end

  describe "bring your own format" do
    rfc2822 = ->(time : Time) { time.to_s("%a, %d %b %Y %H:%M:%S -0000") }
    marshaler = Aws::Record::Marshalers::TimeMarshaler.new(formatter: rfc2822)

    it "supports custom formatting" do
      marshaler.serialize("2016-07-20T16:34:36-07:00").should eq("Wed, 20 Jul 2016 23:34:36 -0000")
    end
  end
end

# Parity: 11/11 examples from spec/aws-record/record/marshalers/time_marshaler_spec.rb (aws-record 2.15.1)
