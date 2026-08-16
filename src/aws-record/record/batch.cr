require "./batch_read"
require "./batch_write"
require "./client_configuration"

# Batch reads and writes across tables and models.
#
# ```
# Aws::Record::Batch.write do |db|
#   db.put(Forum.new(forum_uuid: "a"))
#   db.delete(old_post)
# end
#
# results = Aws::Record::Batch.read do |db|
#   db.find(Forum, forum_uuid: "a")
#   db.find(Post, post_uuid: "b")
# end
# results.each { |item| puts item.class }
# ```
class Aws::Record::Batch
  extend Aws::Record::ClientConfiguration

  # Collects writes in the block and sends them.
  #
  # Unlike the Ruby gem, which builds a fresh client for every call that does not name one, this
  # falls back to the client `Aws::Record::Batch` itself is configured with.
  def self.write(client : Aws::DynamoDB::Client? = nil, & : BatchWrite ->) : BatchWrite
    batch = BatchWrite.new(client_for(client))
    yield batch
    batch.execute!
  end

  # Collects reads in the block and sends the first batch of them.
  #
  # Unlike the Ruby gem, which builds a fresh client for every call that does not name one, this
  # falls back to the client `Aws::Record::Batch` itself is configured with.
  def self.read(client : Aws::DynamoDB::Client? = nil, & : BatchRead ->) : BatchRead
    batch = BatchRead.new(client_for(client))
    yield batch
    batch.execute!
    batch
  end

  private def self.client_for(client : Aws::DynamoDB::Client?) : Aws::DynamoDB::Client
    return dynamodb_client unless client
    client.config.add_user_agent_framework("aws-record")
    client
  end
end
