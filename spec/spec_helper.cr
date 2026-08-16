require "spec"
require "webmock"
require "../src/aws-record-crystal"
require "./support/**"

# The unit suite never talks to the network: every HTTP call goes through webmock. The integration
# suite (`scripts/integration.sh`) does, so it turns real connections back on.
INTEGRATION_RUN = ENV["AWS_INTEGRATION"]? == "1"

Spec.before_each do
  WebMock.reset
  WebMock.allow_net_connect = INTEGRATION_RUN
end
