require "../../spec_helper"

private def wire(value : Aws::DynamoDB::Value) : String
  Aws::DynamoDB::AttributeValue.to_wire(value).to_json
end

private def unwire(json : String) : Aws::DynamoDB::Value
  Aws::DynamoDB::AttributeValue.from_wire(JSON.parse(json))
end

describe Aws::DynamoDB::AttributeValue do
  describe "#to_wire" do
    it "marshals nil as NULL" do
      wire(nil).should eq(%({"NULL":true}))
    end

    it "marshals booleans as BOOL" do
      wire(true).should eq(%({"BOOL":true}))
      wire(false).should eq(%({"BOOL":false}))
    end

    it "marshals strings as S" do
      wire("hello").should eq(%({"S":"hello"}))
    end

    it "marshals an empty string as S" do
      wire("").should eq(%({"S":""}))
    end

    it "marshals integers as N" do
      wire(1_i64).should eq(%({"N":"1"}))
      wire(-42_i64).should eq(%({"N":"-42"}))
    end

    it "marshals floats as N" do
      wire(3.0).should eq(%({"N":"3.0"}))
    end

    it "marshals BigDecimal as N" do
      wire(BigDecimal.new("1.5")).should eq(%({"N":"1.5"}))
    end

    it "marshals a large BigDecimal in the exponent form DynamoDB accepts" do
      # `BigDecimal#to_s` switches to scientific notation for large scales, just like Ruby's
      # (`BigDecimal("12345678901234567890.5").to_s` is `"0.123456789012345678905e20"`).
      # DynamoDB accepts both forms; the round trip below proves no precision is lost.
      wire(BigDecimal.new("12345678901234567890.5")).should eq(%({"N":"1.23456789012345678905e+19"}))
      unwire(%({"N":"1.23456789012345678905e+19"})).should eq(BigDecimal.new("12345678901234567890.5"))
    end

    it "marshals binaries as base64 B" do
      wire("hello".to_slice).should eq(%({"B":"aGVsbG8="}))
    end

    it "marshals string sets as SS" do
      wire(Set{"a"}).should eq(%({"SS":["a"]}))
    end

    it "marshals numeric sets as NS" do
      wire(Set{BigDecimal.new(1)}).should eq(%({"NS":["1.0"]}))
    end

    it "marshals binary sets as BS" do
      wire(Set{"a".to_slice}).should eq(%({"BS":["YQ=="]}))
    end

    it "marshals lists as L" do
      wire([1_i64, "x"] of Aws::DynamoDB::Value).should eq(%({"L":[{"N":"1"},{"S":"x"}]}))
    end

    it "marshals an empty list as L" do
      wire([] of Aws::DynamoDB::Value).should eq(%({"L":[]}))
    end

    it "marshals maps as M" do
      wire(Aws::DynamoDB::Item{"a" => 1_i64}).should eq(%({"M":{"a":{"N":"1"}}}))
    end

    it "marshals nested maps and lists" do
      value = Aws::DynamoDB::Item{
        "outer" => [Aws::DynamoDB::Item{"inner" => nil}.as(Aws::DynamoDB::Value)] of Aws::DynamoDB::Value,
      }
      wire(value).should eq(%({"M":{"outer":{"L":[{"M":{"inner":{"NULL":true}}}]}}}))
    end
  end

  describe "#item_to_wire" do
    it "marshals every attribute of an item" do
      item = Aws::DynamoDB::Item{"id" => 1_i64, "name" => "x"}
      Aws::DynamoDB::AttributeValue.item_to_wire(item).to_json.should eq(%({"id":{"N":"1"},"name":{"S":"x"}}))
    end

    it "marshals an empty item" do
      Aws::DynamoDB::AttributeValue.item_to_wire(Aws::DynamoDB::Item.new).to_json.should eq("{}")
    end
  end

  describe "#from_wire" do
    it "unmarshals S" do
      unwire(%({"S":"hello"})).should eq("hello")
    end

    it "unmarshals an integral N as Int64" do
      value = unwire(%({"N":"1531173732"}))
      value.should be_a(Int64)
      value.should eq(1_531_173_732_i64)
    end

    it "unmarshals a fractional N as BigDecimal" do
      value = unwire(%({"N":"3.5"}))
      value.should be_a(BigDecimal)
      value.should eq(BigDecimal.new("3.5"))
    end

    it "unmarshals a high precision N without losing digits" do
      value = unwire(%({"N":"1.2345678901234567890123456789012345678"}))
      value.should eq(BigDecimal.new("1.2345678901234567890123456789012345678"))
    end

    it "unmarshals B" do
      unwire(%({"B":"aGVsbG8="})).should eq("hello".to_slice)
    end

    it "unmarshals BOOL" do
      unwire(%({"BOOL":true})).should be_true
    end

    it "unmarshals NULL" do
      unwire(%({"NULL":true})).should be_nil
    end

    it "unmarshals SS" do
      unwire(%({"SS":["a","b"]})).should eq(Set{"a", "b"})
    end

    it "unmarshals NS" do
      unwire(%({"NS":["1","2.5"]})).should eq(Set{BigDecimal.new(1), BigDecimal.new("2.5")})
    end

    it "unmarshals BS" do
      unwire(%({"BS":["YQ=="]})).should eq(Set{"a".to_slice})
    end

    it "unmarshals L" do
      unwire(%({"L":[{"N":"1"},{"S":"x"}]})).should eq([1_i64, "x"] of Aws::DynamoDB::Value)
    end

    it "unmarshals M" do
      unwire(%({"M":{"a":{"N":"1"}}})).should eq(Aws::DynamoDB::Item{"a" => 1_i64})
    end

    it "raises on an unknown attribute type" do
      expect_raises(ArgumentError, "Unknown DynamoDB attribute type \"X\"") do
        unwire(%({"X":"1"}))
      end
    end

    it "raises when the value is not an object" do
      expect_raises(ArgumentError, "Expected a DynamoDB attribute value object") do
        unwire(%(["S"]))
      end
    end

    it "raises when more than one attribute type is given" do
      expect_raises(ArgumentError, "Expected exactly one attribute type") do
        unwire(%({"S":"a","N":"1"}))
      end
    end
  end

  describe "#item_from_wire" do
    it "unmarshals every attribute of an item" do
      item = Aws::DynamoDB::AttributeValue.item_from_wire(JSON.parse(%({"id":{"N":"1"},"name":{"S":"x"}})))
      item.should eq(Aws::DynamoDB::Item{"id" => 1_i64, "name" => "x"})
    end

    it "raises when the item is not an object" do
      expect_raises(ArgumentError, "Expected a DynamoDB item object") do
        Aws::DynamoDB::AttributeValue.item_from_wire(JSON.parse("[]"))
      end
    end
  end

  describe "#item_from_wire?" do
    it "returns nil for a missing item" do
      Aws::DynamoDB::AttributeValue.item_from_wire?(nil).should be_nil
    end

    it "returns nil for a JSON null" do
      Aws::DynamoDB::AttributeValue.item_from_wire?(JSON.parse("null")).should be_nil
    end

    it "returns the item when present" do
      Aws::DynamoDB::AttributeValue.item_from_wire?(JSON.parse(%({"a":{"S":"b"}})))
        .should eq(Aws::DynamoDB::Item{"a" => "b"})
    end
  end

  describe "round trips" do
    it "round trips every Value shape" do
      values = [
        nil,
        true,
        "hello",
        "",
        1_i64,
        -1_i64,
        BigDecimal.new("1.5"),
        "bytes".to_slice,
        Set{"a", "b"},
        Set{BigDecimal.new("1.5")},
        Set{"a".to_slice},
        [1_i64, "two", nil] of Aws::DynamoDB::Value,
        Aws::DynamoDB::Item{"nested" => Aws::DynamoDB::Item{"deep" => true}.as(Aws::DynamoDB::Value)},
      ] of Aws::DynamoDB::Value

      values.each do |value|
        round_tripped = Aws::DynamoDB::AttributeValue.from_wire(Aws::DynamoDB::AttributeValue.to_wire(value))
        round_tripped.should eq(value)
      end
    end

    it "round trips floats through their decimal form" do
      # Floats come back as BigDecimal: DynamoDB numbers are decimal, and `Float64` cannot hold
      # all of them exactly. See docs/DIFFERENCES.md.
      round_tripped = Aws::DynamoDB::AttributeValue.from_wire(Aws::DynamoDB::AttributeValue.to_wire(3.5))
      round_tripped.should eq(BigDecimal.new("3.5"))
    end

    it "round trips an item" do
      item = Aws::DynamoDB::Item{"id" => 1_i64, "tags" => Set{"a"}, "meta" => Aws::DynamoDB::Item.new}
      wire = Aws::DynamoDB::AttributeValue.item_to_wire(item)
      Aws::DynamoDB::AttributeValue.item_from_wire(wire).should eq(item)
    end
  end
end
