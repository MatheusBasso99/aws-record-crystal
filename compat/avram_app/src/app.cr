require "avram"
require "aws-record-crystal"

# --- the Lucky app's existing Avram layer -------------------------------
class AppDatabase < Avram::Database
end

AppDatabase.configure do |settings|
  settings.credentials = Avram::Credentials.new(
    database: "x", username: "x", password: "x", hostname: "localhost"
  )
end

Avram.configure(&.database_to_migrate=(AppDatabase))

abstract class BaseModel < Avram::Model
  def self.database : Avram::Database.class
    AppDatabase
  end
end

class Article < BaseModel
  table do
    column title : String
  end
end

# --- this shard, side by side ---------------------------------------------
abstract class DynamoRecord < Aws::Record::Base
  configure_client(client: Aws::DynamoDB::Client.new(stub_responses: true, region: "us-east-1"))
  disable_mutation_tracking
end

class Session < DynamoRecord
  string_attr :sid, hash_key: true
  datetime_attr :created_at
  string_set_attr :roles
  atomic_counter :hits
  set_table_name "sessions"
end

class ShortSession < Session
  epoch_time_attr :ttl
end

models = [Session, ShortSession] of Aws::Record::Base.class
puts models.map(&.table_name)
puts Article.table_name

session = Session.new(sid: "abc", created_at: Time.utc, roles: ["admin"])
puts session.sid, session.created_at, session.roles, session.hits
puts session.key_values
puts Session.mutation_tracking_enabled?, ShortSession.hash_key, ShortSession.attribute_names

# Avram injects `.adapter` into every JSON::Serializable; our wire structs must survive it.
described = Aws::DynamoDB::Types::DescribeTableOutput.from_json(%({"Table":{"TableStatus":"ACTIVE"}}))
puts described.table.try(&.table_status)
puts Aws::DynamoDB::Types::DescribeTableOutput.adapter

# Crystal 1.21's String#present? and Lucky/Avram's Object#present?/blank? coexist.
puts "".present?, nil.blank?
