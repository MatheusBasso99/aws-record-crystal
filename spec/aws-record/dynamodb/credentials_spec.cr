require "../../spec_helper"
require "file_utils"

private def with_shared_files(credentials : String? = nil, config : String? = nil, & : Hash(String, String?) ->)
  dir = File.tempname("aws-record-crystal", "")
  Dir.mkdir_p(dir)
  begin
    vars = {} of String => String?
    if credentials
      path = File.join(dir, "credentials")
      File.write(path, credentials)
      vars["AWS_SHARED_CREDENTIALS_FILE"] = path
    end
    if config
      path = File.join(dir, "config")
      File.write(path, config)
      vars["AWS_CONFIG_FILE"] = path
    end
    yield vars
  ensure
    FileUtils.rm_rf(dir)
  end
end

describe Aws::DynamoDB::Credentials do
  it "keeps the access key, secret and session token" do
    credentials = Aws::DynamoDB::Credentials.new("akid", "secret", "token")
    credentials.access_key_id.should eq("akid")
    credentials.secret_access_key.should eq("secret")
    credentials.session_token.should eq("token")
  end

  it "leaves the session token nil when omitted" do
    Aws::DynamoDB::Credentials.new("akid", "secret").session_token.should be_nil
  end

  it "never prints the secret" do
    credentials = Aws::DynamoDB::Credentials.new("akid", "super-secret", "token")
    credentials.to_s.should eq("Aws::DynamoDB::Credentials(access_key_id=akid)")
    credentials.inspect.should_not contain("super-secret")
  end

  describe ".stubbed" do
    it "returns credentials that never leave the process" do
      Aws::DynamoDB::Credentials.stubbed.access_key_id.should eq("stubbed-akid")
      Aws::DynamoDB::Credentials.stubbed.secret_access_key.should eq("stubbed-secret")
    end
  end

  describe ".from_env" do
    it "reads the standard environment variables" do
      without_aws_env({"AWS_ACCESS_KEY_ID" => "env-akid", "AWS_SECRET_ACCESS_KEY" => "env-secret"}) do
        credentials = Aws::DynamoDB::Credentials.from_env.should_not be_nil
        credentials.access_key_id.should eq("env-akid")
        credentials.secret_access_key.should eq("env-secret")
        credentials.session_token.should be_nil
      end
    end

    it "reads the session token when present" do
      vars = {"AWS_ACCESS_KEY_ID" => "a", "AWS_SECRET_ACCESS_KEY" => "b", "AWS_SESSION_TOKEN" => "c"}
      without_aws_env(vars) do
        Aws::DynamoDB::Credentials.from_env.try(&.session_token).should eq("c")
      end
    end

    it "returns nil when only one of the two is set" do
      without_aws_env({"AWS_ACCESS_KEY_ID" => "a"}) do
        Aws::DynamoDB::Credentials.from_env.should be_nil
      end
    end

    it "treats an empty variable as unset" do
      without_aws_env({"AWS_ACCESS_KEY_ID" => "", "AWS_SECRET_ACCESS_KEY" => "b"}) do
        Aws::DynamoDB::Credentials.from_env.should be_nil
      end
    end
  end

  describe ".from_shared_file" do
    it "reads the default profile" do
      credentials_file = <<-INI
        [default]
        aws_access_key_id = file-akid
        aws_secret_access_key = file-secret
        INI
      with_shared_files(credentials: credentials_file) do |vars|
        without_aws_env(vars) do
          credentials = Aws::DynamoDB::Credentials.from_shared_file.should_not be_nil
          credentials.access_key_id.should eq("file-akid")
          credentials.secret_access_key.should eq("file-secret")
        end
      end
    end

    it "reads the profile named by AWS_PROFILE" do
      credentials_file = <<-INI
        [default]
        aws_access_key_id = default-akid
        aws_secret_access_key = default-secret

        ; a comment
        [dev]
        aws_access_key_id = dev-akid
        aws_secret_access_key = dev-secret
        aws_session_token = dev-token
        INI
      with_shared_files(credentials: credentials_file) do |vars|
        without_aws_env(vars.merge({"AWS_PROFILE" => "dev"})) do
          credentials = Aws::DynamoDB::Credentials.from_shared_file.should_not be_nil
          credentials.access_key_id.should eq("dev-akid")
          credentials.session_token.should eq("dev-token")
        end
      end
    end

    it "returns nil when the profile is missing" do
      with_shared_files(credentials: "[other]\naws_access_key_id = x\n") do |vars|
        without_aws_env(vars) { Aws::DynamoDB::Credentials.from_shared_file.should be_nil }
      end
    end

    it "returns nil when the profile is incomplete" do
      with_shared_files(credentials: "[default]\naws_access_key_id = x\n") do |vars|
        without_aws_env(vars) { Aws::DynamoDB::Credentials.from_shared_file.should be_nil }
      end
    end

    it "returns nil when the file does not exist" do
      without_aws_env({"AWS_SHARED_CREDENTIALS_FILE" => "/nonexistent/credentials"}) do
        Aws::DynamoDB::Credentials.from_shared_file.should be_nil
      end
    end
  end

  describe ".resolve" do
    it "prefers explicit credentials" do
      explicit = Aws::DynamoDB::Credentials.new("explicit", "secret")
      without_aws_env({"AWS_ACCESS_KEY_ID" => "env", "AWS_SECRET_ACCESS_KEY" => "env"}) do
        Aws::DynamoDB::Credentials.resolve(explicit).access_key_id.should eq("explicit")
      end
    end

    it "falls back to the environment" do
      without_aws_env({"AWS_ACCESS_KEY_ID" => "env", "AWS_SECRET_ACCESS_KEY" => "secret"}) do
        Aws::DynamoDB::Credentials.resolve.access_key_id.should eq("env")
      end
    end

    it "falls back to the shared credentials file" do
      credentials_file = "[default]\naws_access_key_id = file\naws_secret_access_key = secret\n"
      with_shared_files(credentials: credentials_file) do |vars|
        without_aws_env(vars) do
          Aws::DynamoDB::Credentials.resolve.access_key_id.should eq("file")
        end
      end
    end

    it "raises when nothing yields credentials" do
      without_aws_env({"AWS_SHARED_CREDENTIALS_FILE" => "/nonexistent/credentials"}) do
        expect_raises(Aws::DynamoDB::Errors::MissingCredentialsError, "AWS_ACCESS_KEY_ID") do
          Aws::DynamoDB::Credentials.resolve
        end
      end
    end
  end
end

describe Aws::DynamoDB::Region do
  describe ".resolve" do
    it "prefers an explicit region" do
      without_aws_env({"AWS_REGION" => "eu-west-1"}) do
        Aws::DynamoDB::Region.resolve("us-east-1").should eq("us-east-1")
      end
    end

    it "reads AWS_REGION" do
      without_aws_env({"AWS_REGION" => "eu-west-1"}) do
        Aws::DynamoDB::Region.resolve.should eq("eu-west-1")
      end
    end

    it "falls back to AWS_DEFAULT_REGION" do
      without_aws_env({"AWS_DEFAULT_REGION" => "ap-south-1"}) do
        Aws::DynamoDB::Region.resolve.should eq("ap-south-1")
      end
    end

    it "falls back to the shared config file" do
      with_shared_files(config: "[profile dev]\nregion = sa-east-1\n") do |vars|
        without_aws_env(vars.merge({"AWS_PROFILE" => "dev"})) do
          Aws::DynamoDB::Region.resolve.should eq("sa-east-1")
        end
      end
    end

    it "reads a default profile written without the profile prefix" do
      with_shared_files(config: "[default]\nregion = ca-central-1\n") do |vars|
        without_aws_env(vars) { Aws::DynamoDB::Region.resolve.should eq("ca-central-1") }
      end
    end

    it "raises when nothing yields a region" do
      without_aws_env({"AWS_CONFIG_FILE" => "/nonexistent/config"}) do
        expect_raises(Aws::DynamoDB::Errors::MissingRegionError, "AWS_REGION") do
          Aws::DynamoDB::Region.resolve
        end
      end
    end
  end
end
