require "json"
require "./errors"
require "./types"

# One canned answer queued on a stubbed `Aws::DynamoDB::Client`.
#
# A stub either carries the wire JSON of a response or an error to raise. `Client#stub_responses`
# builds these for you from the more convenient forms — a typed output shape, an error code, an
# exception, or raw JSON via `Stub.json`.
struct Aws::DynamoDB::Stub
  # The wire JSON this stub answers with, when it is not an error.
  getter body : String?

  # The error this stub raises, when it is not a response.
  getter error : Exception?

  # Creates a stub. Exactly one of *body* and *error* is meaningful.
  def initialize(@body : String? = nil, @error : Exception? = nil) : Nil
  end

  # A stub answering with raw DynamoDB wire JSON.
  #
  # ```
  # client.stub_responses(:scan, Aws::DynamoDB::Stub.json(%({"Items":[{"id":{"N":"1"}}],"Count":1})))
  # ```
  def self.json(raw : String) : Stub
    new(body: raw)
  end

  # A stub answering with an empty response.
  def self.empty : Stub
    new(body: "{}")
  end

  # Builds a stub from a typed output shape.
  def self.from(value : Types::Shape) : Stub
    new(body: value.to_json)
  end

  # Builds a stub that raises *value*.
  def self.from(value : Exception) : Stub
    new(error: value)
  end

  # Builds a stub that raises the DynamoDB error with code *value*.
  def self.from(value : String) : Stub
    new(error: Errors.build(value, "stubbed #{value}"))
  end

  # Returns *value* unchanged.
  def self.from(value : Stub) : Stub
    value
  end

  # The wire JSON of this stub, raising its error when it has one.
  def take : String
    if error = @error
      raise error
    end
    @body || "{}"
  end
end
