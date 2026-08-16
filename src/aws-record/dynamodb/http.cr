require "http/client"
require "awscr-signer"
require "./config"
require "./errors"

# Sends signed DynamoDB requests over a small pool of HTTP connections.
#
# `HTTP::Client` is not safe for concurrent use, and on Crystal 1.21 a fiber may resume on another
# thread, so connections are checked out of a mutex guarded pool for the duration of a request and
# checked back in afterwards. A connection that failed is closed rather than reused.
class Aws::DynamoDB::Transport
  # The raw HTTP response of a DynamoDB call.
  struct Response
    # The HTTP status code.
    getter status : Int32

    # The response body.
    getter body : String

    # The `x-amzn-RequestId` header, when the service sent one.
    getter request_id : String?

    # Creates a response.
    def initialize(@status : Int32, @body : String, @request_id : String? = nil) : Nil
    end

    # Whether the service answered with a success status.
    def success? : Bool
      200 <= @status < 300
    end
  end

  # The configuration this transport signs and sends with.
  getter config : Config

  @pool = Deque(HTTP::Client).new
  @mutex = Mutex.new

  # Creates a transport for *config*.
  def initialize(@config : Config) : Nil
  end

  # Posts *body* to the configured endpoint as the DynamoDB operation *target*.
  #
  # Raises `Errors::NetworkError` when the request could not be sent or the response not read.
  def post(target : String, body : String) : Response
    request = build_request(target, body)
    sign(request)
    exchange(request)
  end

  # Closes every pooled connection.
  def close : Nil
    @mutex.synchronize do
      @pool.each(&.close)
      @pool.clear
    end
  end

  private def exchange(request) : Response
    client = checkout
    begin
      response = client.exec(request)
      checkin(client)
      Response.new(response.status_code, response.body, response.headers["x-amzn-RequestId"]?)
    rescue error : IO::Error | Socket::Error
      client.close
      raise Errors::NetworkError.new("Could not reach #{config.endpoint}: #{error.message}", error)
    end
  end

  private def build_request(target, body) : HTTP::Request
    headers = HTTP::Headers{
      "Host"         => host_header,
      "Content-Type" => "application/x-amz-json-1.0",
      "X-Amz-Target" => target,
      "User-Agent"   => config.user_agent,
      "Accept"       => "application/json",
    }
    HTTP::Request.new("POST", "/", headers, body)
  end

  private def sign(request) : Nil
    credentials = config.credentials
    signer = Awscr::Signer::Signers::V4.new(
      "dynamodb", config.region,
      credentials.access_key_id, credentials.secret_access_key, credentials.session_token
    )
    signer.sign(request)
  end

  private def host_header : String
    endpoint = config.endpoint
    host = endpoint.host || "localhost"
    port = endpoint.port
    port && port != default_port ? "#{host}:#{port}" : host
  end

  private def default_port : Int32
    config.tls? ? 443 : 80
  end

  private def checkout : HTTP::Client
    @mutex.synchronize { @pool.shift? } || build_client
  end

  private def checkin(client) : Nil
    @mutex.synchronize do
      if @pool.size < config.pool_size
        @pool << client
      else
        client.close
      end
    end
  end

  private def build_client : HTTP::Client
    client = HTTP::Client.new(config.endpoint)
    client.connect_timeout = config.connect_timeout
    client.read_timeout = config.read_timeout
    client
  end
end
