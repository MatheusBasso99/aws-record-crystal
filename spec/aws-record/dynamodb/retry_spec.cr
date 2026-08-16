require "../../spec_helper"

describe Aws::DynamoDB::Retry do
  describe ".retry?" do
    it "retries a throttling error" do
      error = Aws::DynamoDB::Errors::ThrottlingException.new
      Aws::DynamoDB::Retry.retry?(error, 1, 3).should be_true
    end

    it "retries a network error" do
      error = Aws::DynamoDB::Errors::NetworkError.new("no route")
      Aws::DynamoDB::Retry.retry?(error, 1, 3).should be_true
    end

    it "does not retry a validation error" do
      error = Aws::DynamoDB::Errors::ValidationException.new
      Aws::DynamoDB::Retry.retry?(error, 1, 3).should be_false
    end

    it "does not retry a cancelled transaction" do
      error = Aws::DynamoDB::Errors::TransactionCanceledException.new
      Aws::DynamoDB::Retry.retry?(error, 1, 3).should be_false
    end

    it "does not retry once the attempts are used up" do
      error = Aws::DynamoDB::Errors::ThrottlingException.new
      Aws::DynamoDB::Retry.retry?(error, 3, 3).should be_false
    end

    it "does not retry an unrelated exception" do
      Aws::DynamoDB::Retry.retry?(ArgumentError.new("nope"), 1, 3).should be_false
    end
  end

  describe ".delay" do
    it "stays within the exponentially growing ceiling" do
      base = 50.milliseconds
      max = 20.seconds
      random = Random.new(1234)
      {1 => 50, 2 => 100, 3 => 200, 4 => 400}.each do |attempt, ceiling_ms|
        delay = Aws::DynamoDB::Retry.delay(attempt, base, max, random)
        delay.should be >= Time::Span.zero
        delay.should be <= ceiling_ms.milliseconds
      end
    end

    it "never exceeds the maximum" do
      random = Random.new(1)
      20.times do |attempt|
        delay = Aws::DynamoDB::Retry.delay(attempt + 1, 50.milliseconds, 1.second, random)
        delay.should be <= 1.second
      end
    end

    it "is zero when the base delay is zero" do
      Aws::DynamoDB::Retry.delay(1, Time::Span.zero, Time::Span.zero).should eq(Time::Span.zero)
    end

    it "jitters, so two delays are not always equal" do
      random = Random.new(99)
      delays = Array.new(20) { Aws::DynamoDB::Retry.delay(5, 50.milliseconds, 20.seconds, random) }
      delays.uniq.size.should be > 1
    end

    it "does not overflow on a very high attempt count" do
      delay = Aws::DynamoDB::Retry.delay(1000, 50.milliseconds, 20.seconds, Random.new(7))
      delay.should be <= 20.seconds
    end
  end
end
