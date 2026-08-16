require "../../spec_helper"

describe Aws::Record::TimeParsing do
  describe ".parse" do
    it "parses RFC 3339" do
      Aws::Record::TimeParsing.parse("2009-02-13T23:31:30Z").should eq(Time.utc(2009, 2, 13, 23, 31, 30))
    end

    it "parses RFC 3339 with an offset, keeping it" do
      parsed = Aws::Record::TimeParsing.parse("2015-11-15T17:12:56+07:00")
      parsed.should eq(Time.parse!("2015-11-15 17:12:56 +0700", "%F %T %z"))
      parsed.utc?.should be_false
    end

    it "parses a space separated time with a numeric offset" do
      parsed = Aws::Record::TimeParsing.parse("2016-07-20 16:31:10 -0700")
      parsed.should eq(Time.utc(2016, 7, 20, 23, 31, 10))
    end

    it "parses a space separated time with a zone name" do
      Aws::Record::TimeParsing.parse("2009-02-13 23:31:30 UTC").should eq(Time.utc(2009, 2, 13, 23, 31, 30))
    end

    it "parses a space separated time with no zone as UTC" do
      Aws::Record::TimeParsing.parse("2009-02-13 23:31:30").should eq(Time.utc(2009, 2, 13, 23, 31, 30))
    end

    it "parses a date only string, which Time.parse_iso8601 rejects" do
      Aws::Record::TimeParsing.parse("2015-11-25").should eq(Time.utc(2015, 11, 25))
    end

    it "parses a slash separated date" do
      Aws::Record::TimeParsing.parse("2015/11/25").should eq(Time.utc(2015, 11, 25))
    end

    it "parses RFC 2822" do
      Aws::Record::TimeParsing.parse("Wed, 20 Jul 2016 23:34:36 -0000")
        .should eq(Time.utc(2016, 7, 20, 23, 34, 36))
    end

    it "parses epoch seconds" do
      Aws::Record::TimeParsing.parse("1531173732").should eq(Time.unix(1_531_173_732))
    end

    it "ignores surrounding whitespace" do
      Aws::Record::TimeParsing.parse("  2015-11-25  ").should eq(Time.utc(2015, 11, 25))
    end

    it "does not let a shorter format swallow a longer string" do
      # "%F" must not match the date prefix of a full timestamp.
      Aws::Record::TimeParsing.parse("2009-02-13 23:31:30 UTC").hour.should eq(23)
      Aws::Record::TimeParsing.parse("2009-02-13T23:31:30Z").hour.should eq(23)
    end

    it "raises for a string it cannot parse" do
      expect_raises(ArgumentError, "Invalid date/time value: \"that time when\"") do
        Aws::Record::TimeParsing.parse("that time when")
      end
    end

    it "raises for an empty string" do
      expect_raises(ArgumentError) { Aws::Record::TimeParsing.parse("   ") }
    end
  end

  describe ".parse?" do
    it "returns nil instead of raising" do
      Aws::Record::TimeParsing.parse?("that time when").should be_nil
      Aws::Record::TimeParsing.parse?("2015-11-25").should_not be_nil
    end
  end
end
