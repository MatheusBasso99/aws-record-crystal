require "spec"
require "webmock"
require "../src/aws-record-crystal"
require "./support/**"

Spec.before_each do
  WebMock.reset
end
