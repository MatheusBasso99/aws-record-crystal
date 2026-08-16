require "../../spec_helper"

describe Aws::DynamoDB::Errors do
  describe "ServiceError" do
    it "defaults its code to the class name" do
      error = Aws::DynamoDB::Errors::ResourceNotFoundException.new("nope")
      error.code.should eq("ResourceNotFoundException")
      error.message.should eq("nope")
      error.http_status.should eq(400)
      error.request_id.should be_nil
    end

    it "keeps an explicit code, status and request id" do
      error = Aws::DynamoDB::Errors::ServiceError.new("boom", "SomeNewException", 500, "req-1")
      error.code.should eq("SomeNewException")
      error.http_status.should eq(500)
      error.request_id.should eq("req-1")
    end

    it "is not retryable by default" do
      Aws::DynamoDB::Errors::ValidationException.new("bad").retryable?.should be_false
    end

    it "is retryable on a 5xx status" do
      Aws::DynamoDB::Errors::ServiceError.new("boom", "Whatever", 503).retryable?.should be_true
    end

    it "is retryable for throttling and capacity errors" do
      Aws::DynamoDB::Errors::ThrottlingException.new.retryable?.should be_true
      Aws::DynamoDB::Errors::ProvisionedThroughputExceededException.new.retryable?.should be_true
      Aws::DynamoDB::Errors::RequestLimitExceeded.new.retryable?.should be_true
      Aws::DynamoDB::Errors::InternalServerError.new.retryable?.should be_true
      Aws::DynamoDB::Errors::TransactionConflictException.new.retryable?.should be_true
    end

    it "is never retryable for conditional, validation and transaction cancellations" do
      Aws::DynamoDB::Errors::ConditionalCheckFailedException.new.retryable?.should be_false
      Aws::DynamoDB::Errors::ValidationException.new.retryable?.should be_false
      Aws::DynamoDB::Errors::TransactionCanceledException.new.retryable?.should be_false
    end
  end

  describe ".code_from_type" do
    it "extracts the code from a qualified __type" do
      Aws::DynamoDB::Errors
        .code_from_type("com.amazonaws.dynamodb.v20120810#ResourceNotFoundException")
        .should eq("ResourceNotFoundException")
    end

    it "returns a bare code unchanged" do
      Aws::DynamoDB::Errors.code_from_type("ValidationException").should eq("ValidationException")
    end

    it "returns nil for a missing or empty type" do
      Aws::DynamoDB::Errors.code_from_type(nil).should be_nil
      Aws::DynamoDB::Errors.code_from_type("").should be_nil
    end
  end

  describe ".build" do
    it "builds the subclass matching the code" do
      error = Aws::DynamoDB::Errors.build("ResourceNotFoundException", "Requested resource not found")
      error.should be_a(Aws::DynamoDB::Errors::ResourceNotFoundException)
      error.message.should eq("Requested resource not found")
    end

    it "builds a plain ServiceError for an unknown code" do
      error = Aws::DynamoDB::Errors.build("BrandNewException", "who knows", 400, "req-9")
      error.class.should eq(Aws::DynamoDB::Errors::ServiceError)
      error.code.should eq("BrandNewException")
      error.request_id.should eq("req-9")
    end

    it "builds every known code" do
      Aws::DynamoDB::Errors::ERROR_CLASSES.each do |code, klass|
        Aws::DynamoDB::Errors.build(code).class.should eq(klass)
      end
    end

    it "attaches the item of a failed conditional check" do
      body = JSON.parse(%({"Item":{"id":{"N":"1"},"name":{"S":"x"}}}))
      error = Aws::DynamoDB::Errors.build("ConditionalCheckFailedException", "nope", 400, nil, body)
      error.as(Aws::DynamoDB::Errors::ConditionalCheckFailedException)
        .item.should eq(Aws::DynamoDB::Item{"id" => 1_i64, "name" => "x"})
    end

    it "leaves the item nil when the service did not return one" do
      error = Aws::DynamoDB::Errors.build("ConditionalCheckFailedException", "nope", 400, nil, JSON.parse("{}"))
      error.as(Aws::DynamoDB::Errors::ConditionalCheckFailedException).item.should be_nil
    end

    it "attaches the cancellation reasons of a cancelled transaction" do
      body = JSON.parse(<<-JSON)
        {"CancellationReasons":[
          {"Code":"None"},
          {"Code":"ConditionalCheckFailed","Message":"The conditional request failed",
           "Item":{"id":{"N":"2"}}}
        ]}
        JSON
      error = Aws::DynamoDB::Errors
        .build("TransactionCanceledException", "Transaction cancelled", 400, nil, body)
        .as(Aws::DynamoDB::Errors::TransactionCanceledException)

      error.cancellation_reasons.size.should eq(2)
      error.cancellation_reasons[0].code.should eq("None")
      error.cancellation_reasons[0].item.should be_nil
      error.cancellation_reasons[1].code.should eq("ConditionalCheckFailed")
      error.cancellation_reasons[1].message.should eq("The conditional request failed")
      error.cancellation_reasons[1].item.should eq(Aws::DynamoDB::Item{"id" => 2_i64})
    end

    it "leaves cancellation reasons empty when the service did not return any" do
      error = Aws::DynamoDB::Errors
        .build("TransactionCanceledException", "Transaction cancelled", 400, nil, JSON.parse("{}"))
        .as(Aws::DynamoDB::Errors::TransactionCanceledException)
      error.cancellation_reasons.should be_empty
    end
  end

  describe "client errors" do
    it "gives MissingRegionError a helpful default message" do
      Aws::DynamoDB::Errors::MissingRegionError.new.message.to_s.should contain("AWS_REGION")
    end

    it "gives MissingCredentialsError a helpful default message" do
      Aws::DynamoDB::Errors::MissingCredentialsError.new.message.to_s.should contain("AWS_ACCESS_KEY_ID")
    end

    it "keeps the underlying error on a NetworkError" do
      cause = IO::Error.new("connection refused")
      error = Aws::DynamoDB::Errors::NetworkError.new("could not connect", cause)
      error.message.should eq("could not connect")
      error.cause_error.should be(cause)
    end

    it "is an Exception, not a ServiceError" do
      Aws::DynamoDB::Errors::WaiterFailed.new("gave up").should be_a(Aws::DynamoDB::Errors::ClientError)
      Aws::DynamoDB::Errors::WaiterFailed.new("gave up").should_not be_a(Aws::DynamoDB::Errors::ServiceError)
    end
  end
end
