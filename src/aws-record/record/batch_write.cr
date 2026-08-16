require "./base"

# A batch of writes to run with one `BatchWriteItem` call.
#
# Built by `Aws::Record::Batch.write`; the writes it collects may span tables and models.
class Aws::Record::BatchWrite
  # Creates an empty batch that writes through *client*.
  def initialize(@client : Aws::DynamoDB::Client) : Nil
    @operations = {} of String => Array(Aws::DynamoDB::Types::WriteRequest)
  end

  # Adds *record* to the batch as a put.
  def put(record : Aws::Record::Base) : Nil
    requests_for(record.class.table_name) << Aws::DynamoDB::Types::WriteRequest.new(
      put_request: Aws::DynamoDB::Types::PutRequest.new(item: record.save_values)
    )
  end

  # Adds *record* to the batch as a delete.
  def delete(record : Aws::Record::Base) : Nil
    requests_for(record.class.table_name) << Aws::DynamoDB::Types::WriteRequest.new(
      delete_request: Aws::DynamoDB::Types::DeleteRequest.new(key: record.key_values)
    )
  end

  # Sends the batch, keeping whatever DynamoDB could not process for a further `#execute!`.
  def execute! : self
    response = @client.batch_write_item(request_items: @operations)
    @operations = response.unprocessed_items || {} of String => Array(Aws::DynamoDB::Types::WriteRequest)
    self
  end

  # Whether every write was processed.
  def complete? : Bool
    unprocessed_items.each_value.all?(&.empty?)
  end

  # The writes DynamoDB could not process, by table name.
  def unprocessed_items : Hash(String, Array(Aws::DynamoDB::Types::WriteRequest))
    @operations
  end

  private def requests_for(table_name) : Array(Aws::DynamoDB::Types::WriteRequest)
    @operations[table_name] ||= [] of Aws::DynamoDB::Types::WriteRequest
  end
end
