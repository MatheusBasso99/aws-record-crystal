require "./errors"

# Reads the AWS shared configuration files, `~/.aws/credentials` and `~/.aws/config`.
#
# Only the INI subset the credential and region providers need is understood: profile sections and
# `key = value` pairs. Nested sub-properties (used by SSO and role configuration) are ignored.
module Aws::DynamoDB::SharedConfig
  extend self

  # Path of the shared credentials file, honouring `AWS_SHARED_CREDENTIALS_FILE`.
  def credentials_path : String
    ENV["AWS_SHARED_CREDENTIALS_FILE"]? || File.join(home, ".aws", "credentials")
  end

  # Path of the shared config file, honouring `AWS_CONFIG_FILE`.
  def config_path : String
    ENV["AWS_CONFIG_FILE"]? || File.join(home, ".aws", "config")
  end

  # Name of the profile to read, honouring `AWS_PROFILE`; `"default"` when unset.
  def profile_name : String
    ENV["AWS_PROFILE"]?.presence || "default"
  end

  # Returns the settings of *profile* in the file at *path*, or `nil` when either is missing.
  #
  # Both spellings of a section header are accepted, so the same reader works for
  # `~/.aws/credentials` (`[dev]`) and `~/.aws/config` (`[profile dev]`).
  def profile(path : String, profile : String) : Hash(String, String)?
    return unless File.file?(path)
    wanted = {"[#{profile}]", "[profile #{profile}]"}
    settings = nil
    File.each_line(path) do |line|
      line = line.strip
      next if line.empty? || line.starts_with?('#') || line.starts_with?(';')
      if line.starts_with?('[')
        break if settings
        settings = Hash(String, String).new if wanted.includes?(line)
      elsif settings
        key, separator, value = line.partition('=')
        settings[key.strip.downcase] = value.strip unless separator.empty?
      end
    end
    settings
  end

  private def home : String
    ENV["HOME"]? || Path.home.to_s
  end
end

# A set of AWS credentials used to sign DynamoDB requests.
#
# Credentials are resolved by `.resolve`, which tries, in order: what the caller passed, the
# environment, and the shared credentials file. IMDS, ECS, SSO and `AssumeRole` are out of scope
# for this shard — pass a `Credentials` built by your own code instead (see `docs/DIFFERENCES.md`).
struct Aws::DynamoDB::Credentials
  # The AWS access key id.
  getter access_key_id : String

  # The AWS secret access key.
  getter secret_access_key : String

  # The session token, for temporary credentials.
  getter session_token : String?

  # Creates a set of credentials.
  def initialize(@access_key_id : String, @secret_access_key : String, @session_token : String? = nil) : Nil
  end

  # The credentials `Client.new(stub_responses: true)` signs with; they never leave the process.
  def self.stubbed : Credentials
    new("stubbed-akid", "stubbed-secret")
  end

  # Resolves credentials from *credentials*, then the environment, then the shared credentials file.
  #
  # Raises `Errors::MissingCredentialsError` when none of them yield a complete set.
  def self.resolve(credentials : Credentials? = nil) : Credentials
    credentials || from_env || from_shared_file || raise Errors::MissingCredentialsError.new
  end

  # Reads `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_SESSION_TOKEN`.
  def self.from_env : Credentials?
    access_key_id = ENV["AWS_ACCESS_KEY_ID"]?.presence
    secret_access_key = ENV["AWS_SECRET_ACCESS_KEY"]?.presence
    return unless access_key_id && secret_access_key
    new(access_key_id, secret_access_key, ENV["AWS_SESSION_TOKEN"]?.presence)
  end

  # Reads the current profile of the shared credentials file.
  def self.from_shared_file : Credentials?
    settings = SharedConfig.profile(SharedConfig.credentials_path, SharedConfig.profile_name)
    return unless settings
    access_key_id = settings["aws_access_key_id"]?.presence
    secret_access_key = settings["aws_secret_access_key"]?.presence
    return unless access_key_id && secret_access_key
    new(access_key_id, secret_access_key, settings["aws_session_token"]?.presence)
  end

  # Prints the access key id only, so that credentials never leak into logs.
  def to_s(io : IO) : Nil
    io << "Aws::DynamoDB::Credentials(access_key_id=" << @access_key_id << ")"
  end

  # :ditto:
  def inspect(io : IO) : Nil
    to_s(io)
  end
end

# Resolves the AWS region a `Client` talks to.
module Aws::DynamoDB::Region
  extend self

  # The region `Client.new(stub_responses: true)` pretends to be in.
  STUBBED = "us-stubbed-1"

  # Resolves the region from *region*, then `AWS_REGION`, `AWS_DEFAULT_REGION` and the shared
  # config file.
  #
  # Raises `Errors::MissingRegionError` when none of them yield one.
  def resolve(region : String? = nil) : String
    region.presence || from_env || from_shared_file || raise Errors::MissingRegionError.new
  end

  # Reads `AWS_REGION`, then `AWS_DEFAULT_REGION`.
  def from_env : String?
    ENV["AWS_REGION"]?.presence || ENV["AWS_DEFAULT_REGION"]?.presence
  end

  # Reads `region` from the current profile of the shared config file.
  def from_shared_file : String?
    SharedConfig.profile(SharedConfig.config_path, SharedConfig.profile_name).try(&.["region"]?).presence
  end
end
