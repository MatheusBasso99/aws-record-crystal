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
# NOTE: this fixture grows as features land (CLAUDE.md §8.9). The point is that it type-checks.
puts Article.table_name
puts Aws::Record::VERSION
puts "".present?, nil.blank?
