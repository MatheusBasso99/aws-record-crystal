require "../../spec_helper"

private def stub_config(**opts) : Aws::DynamoDB::Config
  Aws::DynamoDB::Config.new(**{stub_responses: true, region: "us-east-1"}.merge(opts))
end

describe Aws::DynamoDB::Config do
  describe "region and credentials" do
    it "resolves the region and credentials that were passed" do
      credentials = Aws::DynamoDB::Credentials.new("akid", "secret")
      config = without_aws_env { Aws::DynamoDB::Config.new(region: "eu-west-1", credentials: credentials) }
      config.region.should eq("eu-west-1")
      config.credentials.access_key_id.should eq("akid")
    end

    it "resolves them from the environment" do
      vars = {"AWS_REGION" => "ap-south-1", "AWS_ACCESS_KEY_ID" => "a", "AWS_SECRET_ACCESS_KEY" => "b"}
      config = without_aws_env(vars) { Aws::DynamoDB::Config.new }
      config.region.should eq("ap-south-1")
      config.credentials.access_key_id.should eq("a")
    end

    it "raises when the region cannot be resolved" do
      without_aws_env({"AWS_CONFIG_FILE" => "/nonexistent"}) do
        expect_raises(Aws::DynamoDB::Errors::MissingRegionError) { Aws::DynamoDB::Config.new }
      end
    end

    it "raises when the credentials cannot be resolved" do
      without_aws_env({"AWS_SHARED_CREDENTIALS_FILE" => "/nonexistent"}) do
        expect_raises(Aws::DynamoDB::Errors::MissingCredentialsError) do
          Aws::DynamoDB::Config.new(region: "us-east-1")
        end
      end
    end

    it "needs neither when stubbing responses" do
      config = without_aws_env({"AWS_CONFIG_FILE" => "/nonexistent"}) do
        Aws::DynamoDB::Config.new(stub_responses: true)
      end
      config.stub_responses?.should be_true
      config.region.should eq("us-stubbed-1")
      config.credentials.access_key_id.should eq("stubbed-akid")
    end

    it "still honours an explicit region when stubbing responses" do
      without_aws_env do
        Aws::DynamoDB::Config.new(stub_responses: true, region: "eu-west-2").region.should eq("eu-west-2")
      end
    end
  end

  describe "#endpoint" do
    it "defaults to the regional DynamoDB endpoint" do
      config = without_aws_env { stub_config }
      config.endpoint.to_s.should eq("https://dynamodb.us-east-1.amazonaws.com")
      config.tls?.should be_true
    end

    it "accepts an explicit endpoint string" do
      config = without_aws_env { stub_config(endpoint: "http://localhost:8000") }
      config.endpoint.host.should eq("localhost")
      config.endpoint.port.should eq(8000)
      config.tls?.should be_false
    end

    it "accepts an explicit endpoint URI" do
      config = without_aws_env { stub_config(endpoint: URI.parse("http://127.0.0.1:8000")) }
      config.endpoint.host.should eq("127.0.0.1")
    end

    it "reads AWS_ENDPOINT_URL_DYNAMODB" do
      config = without_aws_env({"AWS_ENDPOINT_URL_DYNAMODB" => "http://localhost:9000"}) { stub_config }
      config.endpoint.port.should eq(9000)
    end

    it "reads AWS_ENDPOINT_URL" do
      config = without_aws_env({"AWS_ENDPOINT_URL" => "http://localhost:9100"}) { stub_config }
      config.endpoint.port.should eq(9100)
    end

    it "prefers the DynamoDB specific endpoint variable" do
      vars = {"AWS_ENDPOINT_URL" => "http://localhost:9100", "AWS_ENDPOINT_URL_DYNAMODB" => "http://localhost:9000"}
      without_aws_env(vars) { stub_config.endpoint.port.should eq(9000) }
    end

    it "raises for an endpoint without a host" do
      without_aws_env do
        expect_raises(ArgumentError, "has no host") { stub_config(endpoint: "not-a-url") }
      end
    end
  end

  describe "defaults" do
    it "uses the documented retry, timeout and pool defaults" do
      config = without_aws_env { stub_config }
      config.max_attempts.should eq(3)
      config.retry_base_delay.should eq(50.milliseconds)
      config.retry_max_delay.should eq(20.seconds)
      config.connect_timeout.should eq(10.seconds)
      config.read_timeout.should eq(60.seconds)
      config.pool_size.should eq(4)
      config.log.should be_a(::Log)
    end

    it "rejects a max_attempts below one" do
      without_aws_env do
        expect_raises(ArgumentError, "max_attempts must be at least 1") { stub_config(max_attempts: 0) }
      end
    end

    it "rejects a pool_size below one" do
      without_aws_env do
        expect_raises(ArgumentError, "pool_size must be at least 1") { stub_config(pool_size: 0) }
      end
    end
  end

  describe "#user_agent" do
    it "names the shard and the Crystal version" do
      config = without_aws_env { stub_config }
      config.user_agent.should eq("aws-record-crystal/#{Aws::Record::VERSION} crystal/#{Crystal::VERSION}")
    end

    it "appends the frameworks it was built with" do
      config = without_aws_env { stub_config(user_agent_frameworks: ["aws-record"]) }
      config.user_agent.should end_with(" aws-record")
      config.user_agent_frameworks.should eq(["aws-record"])
    end

    it "appends a framework added later" do
      config = without_aws_env { stub_config }
      config.add_user_agent_framework("aws-record")
      config.user_agent.should end_with(" aws-record")
    end

    it "ignores a framework that was already added" do
      config = without_aws_env { stub_config }
      config.add_user_agent_framework("aws-record")
      config.add_user_agent_framework("aws-record")
      config.user_agent_frameworks.should eq(["aws-record"])
    end

    it "does not let callers mutate the framework list behind the config's back" do
      config = without_aws_env { stub_config }
      config.user_agent_frameworks << "sneaky"
      config.user_agent_frameworks.should be_empty
    end
  end
end
