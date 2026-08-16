require "../dynamodb/client"

# Gives a model class — and `Aws::Record::Batch` and `Aws::Record::Transactions` — its own DynamoDB
# client.
#
# ```
# class Forum < Aws::Record::Base
#   configure_client(region: "us-east-1")
# end
#
# Forum.configure_client(client: Aws::DynamoDB::Client.new(stub_responses: true))
# ```
#
# Every client this configures announces itself as `aws-record` in its user agent, exactly as the
# Ruby gem does.
module Aws::Record::ClientConfiguration
  macro extended
    @@dynamodb_client : Aws::DynamoDB::Client? = nil
  end

  # Builds and remembers the client this class uses.
  #
  # Passing `client:` uses that client as it is and ignores every other option, mirroring the Ruby
  # gem; anything else is passed to `Aws::DynamoDB::Client.new`.
  def configure_client(client : Aws::DynamoDB::Client? = nil, **opts) : Aws::DynamoDB::Client
    @@dynamodb_client = build_client(client, **opts)
  end

  # The client this class uses, building a default one on first use.
  def dynamodb_client : Aws::DynamoDB::Client
    @@dynamodb_client || configure_client
  end

  # The client this class was explicitly configured with, or `nil`.
  def explicit_dynamodb_client? : Aws::DynamoDB::Client?
    @@dynamodb_client
  end

  private def build_client(client : Aws::DynamoDB::Client?, **opts) : Aws::DynamoDB::Client
    built = client || Aws::DynamoDB::Client.new(**opts)
    built.config.add_user_agent_framework("aws-record")
    built
  end
end
