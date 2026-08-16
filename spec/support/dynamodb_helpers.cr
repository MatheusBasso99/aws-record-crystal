require "webmock"

# One request the fake DynamoDB endpoint received.
record CapturedRequest, method : String, headers : HTTP::Headers, body : String do
  # The parsed request body.
  def json : JSON::Any
    JSON.parse(body)
  end

  # The operation name from the `X-Amz-Target` header.
  def target : String
    headers["X-Amz-Target"]
  end
end

# The endpoint the specs point clients at.
SPEC_ENDPOINT = "https://dynamodb.us-east-1.amazonaws.com"

# A client that never sends a request and answers from its stub queue.
def stub_client(**opts) : Aws::DynamoDB::Client
  Aws::DynamoDB::Client.new(**{stub_responses: true, region: "us-east-1", endpoint: SPEC_ENDPOINT}.merge(opts))
end

# Every call recorded by *client*.
def api_requests(client : Aws::DynamoDB::Client) : Array(Aws::DynamoDB::ApiCall)
  client.api_requests
end

# A client that really sends requests, for use with `stub_endpoint`.
def live_client(**opts) : Aws::DynamoDB::Client
  Aws::DynamoDB::Client.new(**{
    region:           "us-east-1",
    endpoint:         SPEC_ENDPOINT,
    credentials:      Aws::DynamoDB::Credentials.new("akid", "secret"),
    retry_base_delay: Time::Span.zero,
    retry_max_delay:  Time::Span.zero,
  }.merge(opts))
end

# Stubs the DynamoDB endpoint with *responses* (status, body), the last one repeating, and returns
# the array the requests it receives are recorded into.
def stub_endpoint(responses : Array(Tuple(Int32, String)) = [{200, "{}"}],
                  endpoint : String = SPEC_ENDPOINT) : Array(CapturedRequest)
  captured = [] of CapturedRequest
  index = 0
  WebMock.stub(:post, "#{endpoint}/").to_return do |request|
    captured << CapturedRequest.new(request.method, request.headers.dup, WebMock.body(request).to_s)
    status, body = responses[Math.min(index, responses.size - 1)]
    index += 1
    HTTP::Client::Response.new(status, body: body, headers: HTTP::Headers{"x-amzn-RequestId" => "req-1"})
  end
  captured
end

# The body of a DynamoDB error response with *code*.
def error_body(code : String, message : String = "boom") : String
  %({"__type":"com.amazonaws.dynamodb.v20120810##{code}","message":"#{message}"})
end
