require "../../../spec_helper"

describe Aws::Record::Marshalers::DateTimeMarshaler do
  describe "default settings" do
    marshaler = Aws::Record::Marshalers::DateTimeMarshaler.new

    describe "type casting" do
      it "casts nil and empty string as nil" do
        marshaler.type_cast(nil).should be_nil
        marshaler.type_cast("").should be_nil
      end

      it "passes through DateTime objects" do
        # Crystal has no DateTime; `datetime_attr` values are `Time`. See docs/DIFFERENCES.md.
        expected = Time.parse!("2015-11-15 17:12:56 +0700", "%F %T %z")
        marshaler.type_cast(Time.parse!("2015-11-15 17:12:56 +0700", "%F %T %z")).should eq(expected)
      end

      it "converts timestamps to DateTime" do
        marshaler.type_cast(1_234_567_890_i64).should eq(Time.utc(2009, 2, 13, 23, 31, 30))
      end

      it "converts strings to DateTime" do
        marshaler.type_cast("2009-02-13 23:31:30 UTC").should eq(Time.utc(2009, 2, 13, 23, 31, 30))
      end

      it "converts automatically to utc" do
        cast = marshaler.type_cast("2016-07-20 16:31:10 -0700").as(Time)
        cast.should eq(Time.utc(2016, 7, 20, 23, 31, 10))
        cast.utc?.should be_true
      end

      it "raises when unable to parse as a DateTime" do
        expect_raises(ArgumentError) { marshaler.type_cast("that time when") }
      end
    end

    describe "serialization for storage" do
      it "serializes nil as null" do
        marshaler.serialize(nil).should be_nil
      end

      it "serializes DateTime as a string" do
        marshaler.serialize(Time.utc(2009, 2, 13, 23, 31, 30)).should eq("2009-02-13T23:31:30+00:00")
      end
    end
  end

  describe "use local time" do
    marshaler = Aws::Record::Marshalers::DateTimeMarshaler.new(use_local_time: true)

    it "does not automatically convert to utc" do
      expected = Time.parse!("2016-07-20 16:31:10 -0700", "%F %T %z")
      cast = marshaler.type_cast("2016-07-20 16:31:10 -0700").as(Time)
      cast.should eq(expected)
      cast.utc?.should be_false
    end
  end

  describe "bring your own format" do
    # The Ruby spec uses `DateTime#jisx0301`; this formatter produces the same string.
    jisx0301 = ->(time : Time) { "H#{time.year - 1988}.#{time.to_s("%m.%dT%T%:z")}" }
    marshaler = Aws::Record::Marshalers::DateTimeMarshaler.new(formatter: jisx0301)

    it "supports custom formatting" do
      marshaler.serialize("2016-07-20T16:34:36-07:00").should eq("H28.07.20T23:34:36+00:00")
    end
  end

  describe "the remaining RawValue shapes" do
    marshaler = Aws::Record::Marshalers::DateTimeMarshaler.new

    it "casts any number as epoch seconds" do
      marshaler.type_cast(BigDecimal.new(1_531_173_732)).should eq(Time.unix(1_531_173_732))
    end

    it "raises for a value that is not a time at all" do
      expect_raises(ArgumentError, "expected a DateTime value or nil") { marshaler.type_cast(true) }
    end
  end
end

# Parity: 10/10 examples from spec/aws-record/record/marshalers/date_time_marshaler_spec.rb (aws-record 2.15.1)
