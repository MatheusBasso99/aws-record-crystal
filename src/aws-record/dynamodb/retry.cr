require "./errors"

# The retry policy of `Aws::DynamoDB::Client`.
#
# Requests are retried on throttling, capacity and server errors and on transport failures, with
# exponential backoff and full jitter: the delay before attempt *n* is a uniform random span between
# zero and `base * 2 ** (n - 1)`, capped at `max`. Conditional check failures, validation errors and
# cancelled transactions are never retried.
#
# The Ruby gem gets this from the AWS SDK; this client has to provide it.
module Aws::DynamoDB::Retry
  extend self

  # Whether an error raised by attempt *attempt* should be retried.
  def retry?(error : Exception, attempt : Int32, max_attempts : Int32) : Bool
    return false if attempt >= max_attempts
    case error
    when Errors::ServiceError then error.retryable?
    when Errors::NetworkError then true
    else                           false
    end
  end

  # The delay before the attempt following *attempt* (1 for the first attempt).
  #
  # Pass *random* to make the jitter reproducible in specs.
  def delay(attempt : Int32, base : Time::Span, max : Time::Span, random : Random? = nil) : Time::Span
    exponent = Math.min(attempt - 1, 30)
    ceiling = Math.min(base.total_seconds * (2 ** exponent), max.total_seconds)
    return Time::Span.zero unless ceiling > 0
    (random ? random.rand(ceiling) : rand(ceiling)).seconds
  end
end
