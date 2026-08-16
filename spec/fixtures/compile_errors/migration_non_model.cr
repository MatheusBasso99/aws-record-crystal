require "../../../src/aws-record-crystal"

class NotARecord
end

Aws::Record::TableMigration.new(NotARecord)
