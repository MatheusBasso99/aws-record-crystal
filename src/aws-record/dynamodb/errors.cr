require "json"
require "./value"

# Errors raised by `Aws::DynamoDB::Client`.
#
# Service-side failures are `ServiceError`s, one subclass per DynamoDB error code, so that code
# ported from the Ruby gem can keep rescuing the same names
# (`rescue Aws::DynamoDB::Errors::ResourceNotFoundException`). Failures that never reach the
# service — no region, no credentials, a socket error, a waiter that gave up — are `ClientError`s.
module Aws::DynamoDB::Errors
  # Base class for every error returned by the DynamoDB service.
  class ServiceError < Exception
    # The DynamoDB error code, e.g. `"ResourceNotFoundException"`.
    getter code : String

    # The HTTP status of the response that carried the error.
    getter http_status : Int32

    # The `x-amzn-RequestId` of the response, when the service sent one.
    getter request_id : String?

    # Creates an error for DynamoDB error *code*, defaulting the code to this class's own.
    def initialize(message : String? = nil, code : String? = nil,
                   http_status : Int32 = 400, request_id : String? = nil) : Nil
      super(message)
      @code = code || self.class.error_code
      @http_status = http_status
      @request_id = request_id
    end

    # The DynamoDB error code this class represents.
    def self.error_code : String
      name.split("::").last
    end

    # Whether `Aws::DynamoDB::Client` should retry the request that produced this error.
    def retryable? : Bool
      http_status >= 500
    end
  end

  # The requested table or index does not exist, or is not in the `ACTIVE` state.
  class ResourceNotFoundException < ServiceError; end

  # The requested table is being created, updated or deleted.
  class ResourceInUseException < ServiceError; end

  # A conditional write failed its condition expression.
  class ConditionalCheckFailedException < ServiceError
    # The item that failed the condition, present when the request asked for
    # `return_values_on_condition_check_failure`.
    property item : Item?
  end

  # The entire transaction was cancelled; `#cancellation_reasons` says why, per item.
  class TransactionCanceledException < ServiceError
    # One entry per item in the transaction, in request order.
    property cancellation_reasons : Array(CancellationReason) = [] of CancellationReason
  end

  # Another transaction is operating on the same item.
  class TransactionConflictException < ServiceError
    # :inherit:
    def retryable? : Bool
      true
    end
  end

  # A transaction with the same client request token is still being processed.
  class TransactionInProgressException < ServiceError; end

  # A client request token was reused with different request parameters.
  class IdempotentParameterMismatchException < ServiceError; end

  # The request rate exceeded the table's or index's provisioned throughput.
  class ProvisionedThroughputExceededException < ServiceError
    # :inherit:
    def retryable? : Bool
      true
    end
  end

  # The account-level request rate was exceeded.
  class RequestLimitExceeded < ServiceError
    # :inherit:
    def retryable? : Bool
      true
    end
  end

  # The request was throttled.
  class ThrottlingException < ServiceError
    # :inherit:
    def retryable? : Bool
      true
    end
  end

  # The request parameters were rejected by the service.
  class ValidationException < ServiceError; end

  # A single item collection exceeded the 10 GB size limit.
  class ItemCollectionSizeLimitExceededException < ServiceError; end

  # Too many concurrent control-plane operations, or an account limit was reached.
  class LimitExceededException < ServiceError; end

  # An internal error occurred in the service.
  class InternalServerError < ServiceError
    # :inherit:
    def retryable? : Bool
      true
    end
  end

  # The credentials used are not authorized to perform the operation.
  class AccessDeniedException < ServiceError; end

  # The access key id in the request is not valid.
  class UnrecognizedClientException < ServiceError; end

  # The session token in the request has expired.
  class ExpiredTokenException < ServiceError; end

  # The request could not be serialized or deserialized by the service.
  class SerializationException < ServiceError; end

  # Why one item of a cancelled transaction failed.
  struct CancellationReason
    include JSON::Serializable

    # The cancellation code, e.g. `"ConditionalCheckFailed"` or `"None"`.
    @[JSON::Field(key: "Code")]
    getter code : String?

    # A human readable description of the cancellation.
    @[JSON::Field(key: "Message")]
    getter message : String?

    # The item that caused the cancellation, when the service returned one.
    @[JSON::Field(ignore: true)]
    getter item : Item?

    # Creates a cancellation reason.
    def initialize(@code : String? = nil, @message : String? = nil, @item : Item? = nil) : Nil
    end
  end

  # Base class for failures that never reached the DynamoDB service.
  class ClientError < Exception; end

  # No region was configured and none could be discovered from the environment.
  class MissingRegionError < ClientError
    # Creates the error, with a message pointing at the ways a region can be configured.
    def initialize(message : String? = nil) : Nil
      super(message || "Missing region; set `region:` on the client, or the AWS_REGION environment variable")
    end
  end

  # No credentials were configured and none could be discovered from the environment.
  class MissingCredentialsError < ClientError
    # Creates the error, with a message pointing at the ways credentials can be configured.
    def initialize(message : String? = nil) : Nil
      super(message || "Missing credentials; set `credentials:` on the client, or the " \
                       "AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables")
    end
  end

  # The request could not be sent, or the response could not be read.
  class NetworkError < ClientError
    # The underlying `IO`, `Socket` or `OpenSSL` error.
    getter cause_error : Exception?

    # Creates the error, keeping the underlying transport error in `#cause_error`.
    def initialize(message : String? = nil, cause_error : Exception? = nil) : Nil
      super(message)
      @cause_error = cause_error
    end
  end

  # A waiter gave up before the resource reached its expected state.
  class WaiterFailed < ClientError; end

  # Builds the right `ServiceError` subclass for a DynamoDB error response.
  #
  # Unknown codes become a plain `ServiceError`, so a new service error never turns into a crash.
  def self.build(code : String, message : String? = nil, http_status : Int32 = 400,
                 request_id : String? = nil, body : JSON::Any? = nil) : ServiceError
    error_class = ERROR_CLASSES[code]? || ServiceError
    error = error_class.new(message, code, http_status, request_id)
    enrich(error, body) if body
    error
  end

  # Extracts the DynamoDB error code from an error response's `__type` field.
  #
  # `"com.amazonaws.dynamodb.v20120810#ResourceNotFoundException"` becomes
  # `"ResourceNotFoundException"`.
  def self.code_from_type(type : String?) : String?
    return if type.nil? || type.empty?
    type.split("#").last
  end

  private def self.enrich(error : ServiceError, body : JSON::Any) : Nil
    case error
    when ConditionalCheckFailedException
      error.item = AttributeValue.item_from_wire?(body["Item"]?)
    when TransactionCanceledException
      reasons = body["CancellationReasons"]?
      error.cancellation_reasons =
        reasons ? reasons.as_a.map { |reason| cancellation_reason(reason) } : [] of CancellationReason
    end
  end

  private def self.cancellation_reason(json : JSON::Any) : CancellationReason
    CancellationReason.new(
      code: json["Code"]?.try(&.as_s?),
      message: json["Message"]?.try(&.as_s?),
      item: AttributeValue.item_from_wire?(json["Item"]?)
    )
  end

  # Maps DynamoDB error codes to the `ServiceError` subclass that represents them.
  ERROR_CLASSES = {
    "ResourceNotFoundException"                => ResourceNotFoundException,
    "ResourceInUseException"                   => ResourceInUseException,
    "ConditionalCheckFailedException"          => ConditionalCheckFailedException,
    "TransactionCanceledException"             => TransactionCanceledException,
    "TransactionConflictException"             => TransactionConflictException,
    "TransactionInProgressException"           => TransactionInProgressException,
    "IdempotentParameterMismatchException"     => IdempotentParameterMismatchException,
    "ProvisionedThroughputExceededException"   => ProvisionedThroughputExceededException,
    "RequestLimitExceeded"                     => RequestLimitExceeded,
    "ThrottlingException"                      => ThrottlingException,
    "ValidationException"                      => ValidationException,
    "ItemCollectionSizeLimitExceededException" => ItemCollectionSizeLimitExceededException,
    "LimitExceededException"                   => LimitExceededException,
    "InternalServerError"                      => InternalServerError,
    "AccessDeniedException"                    => AccessDeniedException,
    "UnrecognizedClientException"              => UnrecognizedClientException,
    "ExpiredTokenException"                    => ExpiredTokenException,
    "SerializationException"                   => SerializationException,
  } of String => ServiceError.class
end
