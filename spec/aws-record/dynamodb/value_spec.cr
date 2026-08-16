require "../../spec_helper"

module ValueSpec
  # Exercises the `Enumerable` overload through a type that is neither Array nor Set.
  struct Pair
    include Enumerable(Int32)

    def each(& : Int32 ->)
      yield 1
      yield 2
    end
  end
end

describe Aws::DynamoDB::Values do
  describe "#from" do
    it "passes nil through" do
      Aws::DynamoDB::Values.from(nil).should be_nil
    end

    it "passes booleans through" do
      Aws::DynamoDB::Values.from(true).should be_true
      Aws::DynamoDB::Values.from(false).should be_false
    end

    it "passes strings through" do
      Aws::DynamoDB::Values.from("hello").should eq("hello")
    end

    it "converts symbols to strings" do
      Aws::DynamoDB::Values.from(:hello).should eq("hello")
    end

    it "widens integers to Int64" do
      value = Aws::DynamoDB::Values.from(5)
      value.should eq(5_i64)
      value.should be_a(Int64)
      Aws::DynamoDB::Values.from(5_u8).should eq(5_i64)
      Aws::DynamoDB::Values.from(-5_i64).should eq(-5_i64)
    end

    it "converts BigInt to BigDecimal" do
      value = Aws::DynamoDB::Values.from(BigInt.new("123456789012345678901234567890"))
      value.should be_a(BigDecimal)
      value.should eq(BigDecimal.new("123456789012345678901234567890"))
    end

    it "widens floats to Float64" do
      value = Aws::DynamoDB::Values.from(3.5_f32)
      value.should be_a(Float64)
      value.should eq(3.5)
    end

    it "passes BigDecimal through" do
      Aws::DynamoDB::Values.from(BigDecimal.new("1.5")).should eq(BigDecimal.new("1.5"))
    end

    it "passes binary data through" do
      Aws::DynamoDB::Values.from("abc".to_slice).should eq("abc".to_slice)
    end

    it "converts a string set to Set(String)" do
      value = Aws::DynamoDB::Values.from(Set{"a", "b"})
      value.should eq(Set{"a", "b"})
      value.should be_a(Set(String))
    end

    it "converts a symbol set to Set(String)" do
      Aws::DynamoDB::Values.from(Set{:a, :b}).should eq(Set{"a", "b"})
    end

    it "converts a numeric set to Set(BigDecimal)" do
      value = Aws::DynamoDB::Values.from(Set{1, 2})
      value.should be_a(Set(BigDecimal))
      value.should eq(Set{BigDecimal.new(1), BigDecimal.new(2)})
    end

    it "passes a BigDecimal set through" do
      Aws::DynamoDB::Values.from(Set{BigDecimal.new(1)}).should eq(Set{BigDecimal.new(1)})
    end

    it "passes a binary set through" do
      Aws::DynamoDB::Values.from(Set{"a".to_slice}).should eq(Set{"a".to_slice})
    end

    it "converts a hash with string keys to an item" do
      value = Aws::DynamoDB::Values.from({"a" => 1, "b" => "two"})
      value.should eq(Aws::DynamoDB::Item{"a" => 1_i64, "b" => "two"})
    end

    it "converts a hash with symbol keys to an item" do
      Aws::DynamoDB::Values.from({a: 1}).should eq(Aws::DynamoDB::Item{"a" => 1_i64})
    end

    it "converts a named tuple to an item" do
      value = Aws::DynamoDB::Values.from({name: "x", count: 2})
      value.should eq(Aws::DynamoDB::Item{"name" => "x", "count" => 2_i64})
    end

    it "converts an array to a list" do
      value = Aws::DynamoDB::Values.from([1, "two", nil])
      value.should eq([1_i64, "two", nil] of Aws::DynamoDB::Value)
    end

    it "converts a tuple to a list" do
      Aws::DynamoDB::Values.from({1, "two"}).should eq([1_i64, "two"] of Aws::DynamoDB::Value)
    end

    it "converts any other enumerable to a list" do
      Aws::DynamoDB::Values.from(ValueSpec::Pair.new).should eq([1_i64, 2_i64] of Aws::DynamoDB::Value)
    end

    it "converts nested structures recursively" do
      value = Aws::DynamoDB::Values.from({"outer" => [{"inner" => Set{1}}]})
      value.should eq(
        Aws::DynamoDB::Item{
          "outer" => [
            Aws::DynamoDB::Item{"inner" => Set{BigDecimal.new(1)}}.as(Aws::DynamoDB::Value),
          ] of Aws::DynamoDB::Value,
        }
      )
    end

    it "dispatches over a Value union at runtime" do
      values = [1_i64, "x", nil, Set{"a"}] of Aws::DynamoDB::Value
      values.map { |value| Aws::DynamoDB::Values.from(value) }.should eq(values)
    end
  end

  describe "#deep_copy" do
    it "returns scalars unchanged" do
      Aws::DynamoDB::Values.deep_copy(nil).should be_nil
      Aws::DynamoDB::Values.deep_copy(true).should be_true
      Aws::DynamoDB::Values.deep_copy("x").should eq("x")
      Aws::DynamoDB::Values.deep_copy(1_i64).should eq(1_i64)
      Aws::DynamoDB::Values.deep_copy(1.5).should eq(1.5)
      Aws::DynamoDB::Values.deep_copy(BigDecimal.new(1)).should eq(BigDecimal.new(1))
    end

    it "copies binary data" do
      original = "abc".to_slice
      copy = Aws::DynamoDB::Values.deep_copy(original).as(Bytes)
      copy.should eq(original)
      copy[0] = 'z'.ord.to_u8
      original.should eq("abc".to_slice)
    end

    it "copies sets" do
      original = Set{"a"}
      copy = Aws::DynamoDB::Values.deep_copy(original).as(Set(String))
      copy << "b"
      original.should eq(Set{"a"})
    end

    it "copies binary sets deeply" do
      original = Set{"a".to_slice}
      copy = Aws::DynamoDB::Values.deep_copy(original).as(Set(Bytes))
      copy.first[0] = 'z'.ord.to_u8
      original.first.should eq("a".to_slice)
    end

    it "copies numeric sets" do
      original = Set{BigDecimal.new(1)}
      copy = Aws::DynamoDB::Values.deep_copy(original).as(Set(BigDecimal))
      copy << BigDecimal.new(2)
      original.should eq(Set{BigDecimal.new(1)})
    end

    it "copies nested lists and maps deeply" do
      original = Aws::DynamoDB::Item{
        "list" => [Aws::DynamoDB::Item{"a" => 1_i64}.as(Aws::DynamoDB::Value)] of Aws::DynamoDB::Value,
      }
      copy = Aws::DynamoDB::Values.deep_copy(original).as(Aws::DynamoDB::Item)
      copy["list"].as(Array(Aws::DynamoDB::Value))[0].as(Aws::DynamoDB::Item)["a"] = 99_i64
      original["list"].as(Array(Aws::DynamoDB::Value))[0].as(Aws::DynamoDB::Item)["a"].should eq(1_i64)
    end
  end

  describe "#big_decimal" do
    it "keeps BigDecimal values as they are" do
      Aws::DynamoDB::Values.big_decimal(BigDecimal.new("1.10")).should eq(BigDecimal.new("1.10"))
    end

    it "converts floats through their decimal string form" do
      Aws::DynamoDB::Values.big_decimal(0.1).should eq(BigDecimal.new("0.1"))
    end

    it "converts integers" do
      Aws::DynamoDB::Values.big_decimal(7).should eq(BigDecimal.new(7))
    end
  end
end
