require "uri"
require "../version"
require "./credentials"

# Everything a `Aws::DynamoDB::Client` needs to send a request: where to send it, how to sign it,
# how long to wait and how often to retry.
#
# A `Config` is immutable except for `#add_user_agent_framework`, which is mutex guarded, so a
# single client can be shared by every fiber of an application.
class Aws::DynamoDB::Config
  # Default number of attempts (the first try plus retries) per request.
  DEFAULT_MAX_ATTEMPTS = 3

  # Default base delay of the exponential backoff between retries.
  DEFAULT_RETRY_BASE_DELAY = 50.milliseconds

  # Default ceiling of the exponential backoff between retries.
  DEFAULT_RETRY_MAX_DELAY = 20.seconds

  # Default number of pooled HTTP connections.
  DEFAULT_POOL_SIZE = 4

  # The AWS region requests are signed for.
  getter region : String

  # The credentials requests are signed with.
  getter credentials : Credentials

  # The endpoint requests are sent to.
  getter endpoint : URI

  # The number of attempts (the first try plus retries) per request.
  getter max_attempts : Int32

  # The base delay of the exponential backoff between retries.
  getter retry_base_delay : Time::Span

  # The ceiling of the exponential backoff between retries.
  getter retry_max_delay : Time::Span

  # How long to wait for a connection to be established.
  getter connect_timeout : Time::Span

  # How long to wait for a response once a request has been sent.
  getter read_timeout : Time::Span

  # How many HTTP connections the client keeps pooled.
  getter pool_size : Int32

  # The log the client writes to.
  getter log : ::Log

  # Whether the client answers from stubbed responses instead of sending requests.
  getter? stub_responses : Bool

  @mutex = Mutex.new
  @user_agent_frameworks : Array(String)
  @user_agent : String

  # Creates a configuration, resolving *region* and *credentials* from the environment when omitted.
  #
  # With `stub_responses: true` nothing is ever sent, so a stubbed region and stubbed credentials
  # are used and neither has to be configured.
  def initialize(
    region : String? = nil,
    credentials : Credentials? = nil,
    endpoint : (String | URI)? = nil,
    stub_responses : Bool = false,
    max_attempts : Int32 = DEFAULT_MAX_ATTEMPTS,
    retry_base_delay : Time::Span = DEFAULT_RETRY_BASE_DELAY,
    retry_max_delay : Time::Span = DEFAULT_RETRY_MAX_DELAY,
    connect_timeout : Time::Span = 10.seconds,
    read_timeout : Time::Span = 60.seconds,
    pool_size : Int32 = DEFAULT_POOL_SIZE,
    user_agent_frameworks : Array(String) = [] of String,
    log : ::Log = Log,
  ) : Nil
    raise ArgumentError.new("max_attempts must be at least 1, got #{max_attempts}") if max_attempts < 1
    raise ArgumentError.new("pool_size must be at least 1, got #{pool_size}") if pool_size < 1
    @stub_responses = stub_responses
    @region = stub_responses ? (region.presence || Region.from_env || Region::STUBBED) : Region.resolve(region)
    @credentials = stub_responses ? (credentials || Credentials.stubbed) : Credentials.resolve(credentials)
    @endpoint = self.class.resolve_endpoint(endpoint, @region)
    @max_attempts = max_attempts
    @retry_base_delay = retry_base_delay
    @retry_max_delay = retry_max_delay
    @connect_timeout = connect_timeout
    @read_timeout = read_timeout
    @pool_size = pool_size
    @log = log
    @user_agent_frameworks = user_agent_frameworks.dup
    @user_agent = build_user_agent
  end

  # Whether requests are sent over TLS.
  def tls? : Bool
    @endpoint.scheme == "https"
  end

  # The `User-Agent` header the client sends.
  def user_agent : String
    @user_agent
  end

  # The framework names appended to the `User-Agent` header.
  def user_agent_frameworks : Array(String)
    @mutex.synchronize { @user_agent_frameworks.dup }
  end

  # Appends *name* to the `User-Agent` header, mirroring the Ruby gem's
  # `client.config.user_agent_frameworks << 'aws-record'`. Appending the same name twice is a no-op.
  def add_user_agent_framework(name : String) : Nil
    @mutex.synchronize do
      next if @user_agent_frameworks.includes?(name)
      @user_agent_frameworks << name
      @user_agent = build_user_agent
    end
  end

  # Resolves the endpoint from *endpoint*, then `AWS_ENDPOINT_URL_DYNAMODB`, then `AWS_ENDPOINT_URL`,
  # falling back to the regional DynamoDB endpoint.
  def self.resolve_endpoint(endpoint : (String | URI)?, region : String) : URI
    endpoint ||= ENV["AWS_ENDPOINT_URL_DYNAMODB"]?.presence || ENV["AWS_ENDPOINT_URL"]?.presence
    return URI.parse("https://dynamodb.#{region}.amazonaws.com") unless endpoint
    uri = endpoint.is_a?(URI) ? endpoint : URI.parse(endpoint)
    raise ArgumentError.new("Endpoint #{endpoint} has no host") unless uri.host
    uri
  end

  private def build_user_agent : String
    String.build do |io|
      io << "aws-record-crystal/" << Aws::Record::VERSION << " crystal/" << Crystal::VERSION
      @user_agent_frameworks.each { |framework| io << ' ' << framework }
    end
  end
end
