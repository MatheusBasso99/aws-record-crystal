# Port of `lib/aws-record.rb` — requires the DynamoDB client layer and then the record layer.
#
# Crystal is mostly order-independent, but macros used by `record/base.cr` must be defined
# before use, so the order below is explicit and intentional.
require "./aws-record/version"
