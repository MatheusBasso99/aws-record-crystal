require "log"

# Object mapping abstraction for Amazon DynamoDB, ported from Amazon's `aws-record` Ruby gem.
#
# Models subclass `Aws::Record::Base` and declare their attributes with the `*_attr` macros:
#
# ```
# class Forum < Aws::Record::Base
#   string_attr :forum_uuid, hash_key: true
#   integer_attr :post_count
# end
# ```
module Aws::Record
  # Log source for the record layer. Plug a backend into `"aws.record"` to see it.
  Log = ::Log.for("aws.record")

  # Version of this shard.
  VERSION = "0.1.0"

  # Version of the `aws-record` Ruby gem this shard is a port of.
  UPSTREAM_VERSION = "2.15.1"
end
