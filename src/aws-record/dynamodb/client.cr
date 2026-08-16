require "./config"
require "./errors"
require "./http"
require "./operation"
require "./paginator"
require "./retry"
require "./stub"
require "./types"

# A minimal, typed client for the Amazon DynamoDB JSON API.
#
# Every operation has two overloads: one taking its typed input shape, and one taking that shape's
# keyword arguments. Naming an option the operation does not have is a compile error.
#
# ```
# client = Aws::DynamoDB::Client.new(region: "us-east-1")
# client.put_item(table_name: "Forum", item: Aws::DynamoDB::Item{"uuid" => "abc"})
# client.get_item(Aws::DynamoDB::Types::GetItemInput.new(
#   table_name: "Forum", key: Aws::DynamoDB::Item{"uuid" => "abc"}
# )).item
# ```
#
# With `stub_responses: true` nothing is sent: responses come from the queue set by
# `#stub_responses`, and every call is recorded in `#api_requests`.
class Aws::DynamoDB::Client
  # How long waiters wait between polls by default.
  DEFAULT_WAITER_DELAY = 20.seconds

  # How many times waiters poll before giving up by default.
  DEFAULT_WAITER_ATTEMPTS = 25

  # The configuration this client sends with.
  getter config : Config

  @transport : Transport?
  @stubs = {} of Operation => Array(Stub)
  @api_requests = [] of ApiCall
  @before_request = [] of Proc(ApiCall, Nil)
  @mutex = Mutex.new

  # Creates a client from a ready-made configuration.
  def initialize(@config : Config) : Nil
    @transport = Transport.new(@config) unless @config.stub_responses?
  end

  # Creates a client, building its `Config` from *opts*.
  def initialize(**opts) : Nil
    initialize(Config.new(**opts))
  end

  # Defines the two overloads of a DynamoDB operation: one taking the typed input shape, one taking
  # that shape's keyword arguments.
  macro operation(name, shape)
    def {{ name.id }}(input : Types::{{ shape.id }}Input) : Types::{{ shape.id }}Output
      Types::{{ shape.id }}Output.from_json(call(Operation::{{ shape.id }}, input))
    end

    def {{ name.id }}(**args) : Types::{{ shape.id }}Output
      {{ name.id }}(Types::{{ shape.id }}Input.new(**args))
    end
  end

  operation put_item, PutItem
  operation get_item, GetItem
  operation update_item, UpdateItem
  operation delete_item, DeleteItem
  operation query, Query
  operation scan, Scan
  operation batch_get_item, BatchGetItem
  operation batch_write_item, BatchWriteItem
  operation transact_get_items, TransactGetItems
  operation transact_write_items, TransactWriteItems
  operation create_table, CreateTable
  operation update_table, UpdateTable
  operation delete_table, DeleteTable
  operation describe_table, DescribeTable
  operation list_tables, ListTables
  operation describe_time_to_live, DescribeTimeToLive
  operation update_time_to_live, UpdateTimeToLive

  # The pages of a query, fetched lazily.
  def query_pages(input : Types::QueryInput) : Pages(Types::QueryInput, Types::QueryOutput)
    Pages(Types::QueryInput, Types::QueryOutput).new(
      input, ->(page_input : Types::QueryInput) : Types::QueryOutput { query(page_input) }
    )
  end

  # :ditto:
  def query_pages(**args) : Pages(Types::QueryInput, Types::QueryOutput)
    query_pages(Types::QueryInput.new(**args))
  end

  # The pages of a scan, fetched lazily.
  def scan_pages(input : Types::ScanInput) : Pages(Types::ScanInput, Types::ScanOutput)
    Pages(Types::ScanInput, Types::ScanOutput).new(
      input, ->(page_input : Types::ScanInput) : Types::ScanOutput { scan(page_input) }
    )
  end

  # :ditto:
  def scan_pages(**args) : Pages(Types::ScanInput, Types::ScanOutput)
    scan_pages(Types::ScanInput.new(**args))
  end

  # Polls `describe_table` until *table_name* is `ACTIVE`.
  #
  # Raises `Errors::WaiterFailed` when it still is not after *max_attempts* polls.
  def wait_until_table_exists(table_name : String, delay : Time::Span = DEFAULT_WAITER_DELAY,
                              max_attempts : Int32 = DEFAULT_WAITER_ATTEMPTS) : Types::TableDescription
    max_attempts.times do |attempt|
      table = describe_table_or_nil(table_name)
      return table if table && table.table_status == "ACTIVE"
      sleep(waiter_delay(delay)) unless attempt == max_attempts - 1
    end
    raise Errors::WaiterFailed.new("Table #{table_name} was not ACTIVE after #{max_attempts} attempts")
  end

  # Polls `describe_table` until *table_name* no longer exists.
  #
  # Raises `Errors::WaiterFailed` when it still does after *max_attempts* polls.
  def wait_until_table_not_exists(table_name : String, delay : Time::Span = DEFAULT_WAITER_DELAY,
                                  max_attempts : Int32 = DEFAULT_WAITER_ATTEMPTS) : Nil
    max_attempts.times do |attempt|
      return if describe_table_or_nil(table_name).nil?
      sleep(waiter_delay(delay)) unless attempt == max_attempts - 1
    end
    raise Errors::WaiterFailed.new("Table #{table_name} still existed after #{max_attempts} attempts")
  end

  # Queues the answers this client gives for *operation*, in order.
  #
  # A stub can be a typed output shape, an `Exception` to raise, a `String` naming a DynamoDB error
  # code, or `Stub.json` for raw wire JSON. The last stub is repeated once the queue runs out, and
  # an operation with no stub answers with an empty response.
  #
  # ```
  # client.stub_responses(:describe_table, "ResourceNotFoundException", describe_table_output)
  # ```
  def stub_responses(operation : Operation, *stubs : Types::Shape | Exception | String | Stub) : Nil
    queued = [] of Stub
    stubs.each { |stub| queued << Stub.from(stub) }
    @mutex.synchronize { @stubs[operation] = queued }
  end

  # Every call made through this client, oldest first.
  def api_requests : Array(ApiCall)
    @mutex.synchronize { @api_requests.dup }
  end

  # Forgets every recorded call.
  def clear_api_requests : Nil
    @mutex.synchronize { @api_requests.clear }
  end

  # Registers a callback run with every call before it is sent.
  #
  # This is the Crystal counterpart of the Ruby gem's `client.handle { |ctx| … }`.
  def before_request(&callback : ApiCall ->) : Nil
    @mutex.synchronize { @before_request << callback }
  end

  # Closes every pooled connection.
  def close : Nil
    @transport.try(&.close)
  end

  private def call(operation : Operation, input : Types::Shape) : String
    api_call = ApiCall.new(operation, input)
    callbacks = @mutex.synchronize do
      @api_requests << api_call
      @before_request.dup
    end
    callbacks.each(&.call(api_call))
    return next_stub(operation).take if config.stub_responses?
    dispatch(operation, input.to_json)
  end

  private def dispatch(operation : Operation, body : String) : String
    transport = @transport
    raise Errors::ClientError.new("This client is stubbed, so it cannot send requests") unless transport
    attempt = 1
    loop do
      response = transport.post(operation.target, body)
      return response.body if response.success?
      raise error_for(response)
    rescue error : Errors::ServiceError | Errors::NetworkError
      raise error unless Retry.retry?(error, attempt, config.max_attempts)
      backoff = Retry.delay(attempt, config.retry_base_delay, config.retry_max_delay)
      Log.debug { "Retrying #{operation} after #{error.class}: #{error.message} (attempt #{attempt})" }
      sleep(backoff)
      attempt += 1
    end
  end

  private def error_for(response : Transport::Response) : Errors::ServiceError
    body = parse_body(response.body)
    code = Errors.code_from_type(body.try(&.["__type"]?).try(&.as_s?)) || "ServiceError"
    message = body.try { |json| (json["message"]? || json["Message"]?).try(&.as_s?) }
    Errors.build(code, message, response.status, response.request_id, body)
  end

  private def parse_body(body : String) : JSON::Any?
    return if body.empty?
    JSON.parse(body)
  rescue JSON::ParseException
    nil
  end

  private def next_stub(operation : Operation) : Stub
    @mutex.synchronize do
      queue = @stubs[operation]?
      next Stub.empty if queue.nil? || queue.empty?
      queue.size > 1 ? queue.shift : queue.first
    end
  end

  private def describe_table_or_nil(table_name : String) : Types::TableDescription?
    describe_table(table_name: table_name).table
  rescue Errors::ResourceNotFoundException
    nil
  end

  private def waiter_delay(delay : Time::Span) : Time::Span
    config.stub_responses? ? Time::Span.zero : delay
  end
end
