require "../../spec_helper"

module ClientConfigurationSpec
  class InheritParent < Aws::Record::Base
  end

  class InheritChild < InheritParent
  end

  class OwnClientParent < Aws::Record::Base
  end

  class OwnClientChild < OwnClientParent
  end

  class UserAgentModel < Aws::Record::Base
  end
end

describe "ClientConfiguration" do
  describe "inheritance support for dynamodb client" do
    it "should have child model inherit dynamodb client from parent model" do
      client = stub_client
      ClientConfigurationSpec::InheritParent.configure_client(client: client)
      ClientConfigurationSpec::InheritChild.dynamodb_client

      ClientConfigurationSpec::InheritParent.dynamodb_client
        .should be(ClientConfigurationSpec::InheritChild.dynamodb_client)
    end

    it "should have child model maintain its own dynamodb client if defined in model" do
      ClientConfigurationSpec::OwnClientParent.configure_client(client: stub_client)
      ClientConfigurationSpec::OwnClientChild.configure_client(client: stub_client)

      ClientConfigurationSpec::OwnClientChild.dynamodb_client
        .should_not be(ClientConfigurationSpec::OwnClientParent.dynamodb_client)
    end
  end

  describe "#configure_client" do
    it "announces aws-record in the user agent of the client it configures" do
      client = stub_client
      ClientConfigurationSpec::UserAgentModel.configure_client(client: client)
      client.config.user_agent_frameworks.should eq(["aws-record"])
      client.config.user_agent.should end_with(" aws-record")
    end

    it "builds a client from the options it is given" do
      client = without_aws_env do
        ClientConfigurationSpec::UserAgentModel.configure_client(stub_responses: true, region: "eu-west-1")
      end
      client.config.region.should eq("eu-west-1")
      client.config.stub_responses?.should be_true
    end

    it "ignores every other option when a client is given" do
      client = stub_client
      configured = ClientConfigurationSpec::UserAgentModel.configure_client(client: client, region: "eu-west-1")
      configured.should be(client)
      configured.config.region.should eq("us-east-1")
    end
  end
end

# Parity: 2/2 examples from spec/aws-record/record/client_configuration_spec.rb (aws-record 2.15.1),
# plus extras
