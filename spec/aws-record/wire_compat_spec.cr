require "../spec_helper"

# Data written by this shard must be readable by the Ruby gem, and the other way round. Every row of
# the wire compatibility table in CLAUDE.md §4.6 is asserted here, at the level of the marshaler that
# produces it and of the attribute value that goes on the wire.
private def stored(marshaler : Aws::Record::Marshalers::Marshaler, value : Aws::Record::RawValue) : String
  Aws::DynamoDB::AttributeValue.to_wire(marshaler.serialize(value)).to_json
end

describe "wire compatibility with the aws-record Ruby gem" do
  describe "date_attr" do
    it "stores a date as an S attribute in %F" do
      marshaler = Aws::Record::Marshalers::DateMarshaler.new
      stored(marshaler, Time.utc(2015, 11, 25)).should eq(%({"S":"2015-11-25"}))
      stored(marshaler, "2015-11-25").should eq(%({"S":"2015-11-25"}))
    end
  end

  describe "time_attr" do
    it "stores a UTC time as an S attribute ending in Z, like Ruby's Time#iso8601" do
      marshaler = Aws::Record::Marshalers::TimeMarshaler.new
      stored(marshaler, Time.utc(2009, 2, 13, 23, 31, 30)).should eq(%({"S":"2009-02-13T23:31:30Z"}))
    end

    it "stores a local time with its numeric offset when use_local_time is set" do
      marshaler = Aws::Record::Marshalers::TimeMarshaler.new(use_local_time: true)
      stored(marshaler, "2015-11-15 17:12:56 +0700").should eq(%({"S":"2015-11-15T17:12:56+07:00"}))
    end
  end

  describe "datetime_attr" do
    it "always stores a numeric offset, like Ruby's DateTime#iso8601" do
      marshaler = Aws::Record::Marshalers::DateTimeMarshaler.new
      stored(marshaler, Time.utc(2009, 2, 13, 23, 31, 30)).should eq(%({"S":"2009-02-13T23:31:30+00:00"}))
    end
  end

  describe "epoch_time_attr" do
    it "stores whole epoch seconds as an N attribute" do
      marshaler = Aws::Record::Marshalers::EpochTimeMarshaler.new
      stored(marshaler, Time.utc(2018, 7, 9, 22, 2, 12)).should eq(%({"N":"1531173732"}))
    end
  end

  describe "integer_attr" do
    it "stores an integer as an N attribute without a fractional part" do
      stored(Aws::Record::Marshalers::IntegerMarshaler.new, 1_i64).should eq(%({"N":"1"}))
    end
  end

  describe "float_attr" do
    it "stores a float as an N attribute the way Ruby's Float#to_s writes it" do
      stored(Aws::Record::Marshalers::FloatMarshaler.new, 3.0).should eq(%({"N":"3.0"}))
    end
  end

  describe "boolean_attr" do
    it "stores a boolean as a BOOL attribute" do
      marshaler = Aws::Record::Marshalers::BooleanMarshaler.new
      stored(marshaler, true).should eq(%({"BOOL":true}))
      stored(marshaler, false).should eq(%({"BOOL":false}))
    end
  end

  describe "string_attr" do
    it "stores a string as an S attribute" do
      stored(Aws::Record::Marshalers::StringMarshaler.new, "hello").should eq(%({"S":"hello"}))
    end

    it "does not persist an empty string" do
      Aws::Record::Marshalers::StringMarshaler.new.serialize("").should be_nil
    end
  end

  describe "string_set_attr" do
    it "stores a string set as an SS attribute" do
      stored(Aws::Record::Marshalers::StringSetMarshaler.new, Set{"a", "b"}).should eq(%({"SS":["a","b"]}))
    end

    it "does not persist an empty set" do
      Aws::Record::Marshalers::StringSetMarshaler.new.serialize(Set(String).new).should be_nil
    end
  end

  describe "numeric_set_attr" do
    it "stores a numeric set as an NS attribute" do
      marshaler = Aws::Record::Marshalers::NumericSetMarshaler.new
      stored(marshaler, Set{BigDecimal.new(1)}).should eq(%({"NS":["1.0"]}))
    end

    it "does not persist an empty set" do
      Aws::Record::Marshalers::NumericSetMarshaler.new.serialize(Set(BigDecimal).new).should be_nil
    end
  end

  describe "list_attr" do
    it "stores a list as an L attribute" do
      marshaler = Aws::Record::Marshalers::ListMarshaler.new
      stored(marshaler, [1_i64, "two"] of Aws::DynamoDB::Value).should eq(%({"L":[{"N":"1"},{"S":"two"}]}))
    end
  end

  describe "map_attr" do
    it "stores a map as an M attribute" do
      marshaler = Aws::Record::Marshalers::MapMarshaler.new
      stored(marshaler, Aws::DynamoDB::Item{"a" => 1_i64}).should eq(%({"M":{"a":{"N":"1"}}}))
    end
  end

  describe "persist_nil" do
    it "stores nil as a NULL attribute when asked for" do
      attribute = Aws::Record::Attribute.new(
        :body, marshaler: Aws::Record::Marshalers::StringMarshaler.new, persist_nil: true
      )
      attribute.persist_nil?.should be_true
      Aws::DynamoDB::AttributeValue.to_wire(attribute.serialize(nil)).to_json.should eq(%({"NULL":true}))
    end
  end

  describe "expression placeholder tokens" do
    it "walks the same substitution names as Ruby's String#succ" do
      # `_build_update_expression` names placeholders `#UE_A`, `#UE_B`, … and `:ue_a`, `:ue_b`, …
      # by calling `String#succ`; the two languages must agree on where it rolls over.
      "UE_A".succ.should eq("UE_B")
      "UE_Z".succ.should eq("UF_A")
      "ue_a".succ.should eq("ue_b")
      "ue_z".succ.should eq("uf_a")
      "BUILDERA".succ.should eq("BUILDERB")
      "buildera".succ.should eq("builderb")
      "BUILDERZ".succ.should eq("BUILDESA")
    end
  end
end
