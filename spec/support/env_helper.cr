# Runs the block with *vars* applied to `ENV`, restoring every touched variable afterwards.
#
# A `nil` value removes the variable for the duration of the block, which is how specs make sure
# they see no ambient AWS configuration.
def with_env(vars : Hash(String, String?), &)
  previous = {} of String => String?
  vars.each do |key, value|
    previous[key] = ENV[key]?
    if value
      ENV[key] = value
    else
      ENV.delete(key)
    end
  end
  begin
    yield
  ensure
    previous.each do |key, value|
      if value
        ENV[key] = value
      else
        ENV.delete(key)
      end
    end
  end
end

# Runs the block with no ambient AWS environment variables at all, plus any *vars* given.
def without_aws_env(vars : Hash(String, String?) = {} of String => String?, &)
  cleared = {} of String => String?
  %w[
    AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    AWS_REGION AWS_DEFAULT_REGION AWS_PROFILE
    AWS_SHARED_CREDENTIALS_FILE AWS_CONFIG_FILE
    AWS_ENDPOINT_URL AWS_ENDPOINT_URL_DYNAMODB
  ].each { |key| cleared[key] = nil }
  with_env(cleared.merge(vars)) { yield }
end
