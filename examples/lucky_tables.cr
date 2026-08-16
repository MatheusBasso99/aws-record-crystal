require "./lucky_app"

# The "Creating the tables" part of the README's Lucky/Avram section. Builds on lucky_app.cr
# (DYNAMODB, Session and Cart).

# db/dynamodb/tables.cr
module DynamoTables
  SESSIONS = Aws::Record::TableConfig.define do |table|
    table.model_class(Session)             # first: ttl_attribute is validated against the model
    table.billing_mode("PAY_PER_REQUEST")  # no capacity to plan; PROVISIONED needs read/write_capacity_units
    table.ttl_attribute(:expires_at)       # an epoch_time_attr, which is what DynamoDB TTL expects
    table.client_options(client: DYNAMODB) # same endpoint and credentials as the models
  end

  CARTS = Aws::Record::TableConfig.define do |table|
    table.model_class(Cart)
    table.billing_mode("PAY_PER_REQUEST")
    table.client_options(client: DYNAMODB)
  end

  ALL = [SESSIONS, CARTS]
end

# Stand-in for the `lucky_task` shard, so the task below type-checks here without Lucky installed.
# In an app the real `LuckyTask::Task` provides `summary` and runs `call`.
module LuckyTask
  abstract class Task
    macro summary(text)
    end

    abstract def call
  end
end

# tasks/dynamodb/migrate.cr — `lucky dynamodb.migrate`
class Dynamodb::Migrate < LuckyTask::Task
  summary "Create or update the DynamoDB tables (idempotent)"

  def call
    DynamoTables::ALL.each(&.migrate!)
  end
end
