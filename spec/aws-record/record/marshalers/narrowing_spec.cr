require "../../../spec_helper"

# `.narrow` is what gives generated attribute getters their precise return type: it recovers the
# `Cast` type of a marshaler from the `RawValue` that `Aws::Record::Attribute#type_cast` returns.
# It has no counterpart in the Ruby gem, where attributes are untyped.
describe "Aws::Record::Marshalers narrowing" do
  it "narrows a string" do
    Aws::Record::Marshalers::StringMarshaler.narrow("x").should eq("x")
    Aws::Record::Marshalers::StringMarshaler.narrow(nil).should be_nil
  end

  it "narrows a boolean" do
    Aws::Record::Marshalers::BooleanMarshaler.narrow(true).should be_true
    Aws::Record::Marshalers::BooleanMarshaler.narrow(nil).should be_nil
  end

  it "narrows an integer" do
    Aws::Record::Marshalers::IntegerMarshaler.narrow(1_i64).should eq(1_i64)
    Aws::Record::Marshalers::IntegerMarshaler.narrow(nil).should be_nil
  end

  it "narrows a float" do
    Aws::Record::Marshalers::FloatMarshaler.narrow(1.5).should eq(1.5)
    Aws::Record::Marshalers::FloatMarshaler.narrow(nil).should be_nil
  end

  it "narrows the time based marshalers" do
    time = Time.utc(2015, 11, 25)
    Aws::Record::Marshalers::DateMarshaler.narrow(time).should eq(time)
    Aws::Record::Marshalers::DateTimeMarshaler.narrow(time).should eq(time)
    Aws::Record::Marshalers::TimeMarshaler.narrow(time).should eq(time)
    Aws::Record::Marshalers::EpochTimeMarshaler.narrow(time).should eq(time)
    Aws::Record::Marshalers::TimeMarshaler.narrow(nil).should be_nil
  end

  it "narrows a list" do
    list = [1_i64] of Aws::DynamoDB::Value
    Aws::Record::Marshalers::ListMarshaler.narrow(list).should eq(list)
    Aws::Record::Marshalers::ListMarshaler.narrow(nil).should be_nil
  end

  it "narrows a map" do
    map = Aws::DynamoDB::Item{"a" => 1_i64}
    Aws::Record::Marshalers::MapMarshaler.narrow(map).should eq(map)
    Aws::Record::Marshalers::MapMarshaler.narrow(nil).should be_nil
  end

  it "narrows a string set, defaulting to an empty set" do
    Aws::Record::Marshalers::StringSetMarshaler.narrow(Set{"a"}).should eq(Set{"a"})
    Aws::Record::Marshalers::StringSetMarshaler.narrow(nil).should eq(Set(String).new)
  end

  it "narrows a numeric set, defaulting to an empty set" do
    set = Set{BigDecimal.new(1)}
    Aws::Record::Marshalers::NumericSetMarshaler.narrow(set).should eq(set)
    Aws::Record::Marshalers::NumericSetMarshaler.narrow(nil).should eq(Set(BigDecimal).new)
  end

  it "leaves a value untouched for the default marshaler" do
    Aws::Record::Marshalers::DefaultMarshaler.narrow("x").should eq("x")
  end
end
