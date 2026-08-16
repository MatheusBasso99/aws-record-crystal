require "../spec_helper"

describe Aws::Record do
  describe "VERSION" do
    it "is a semantic version string" do
      Aws::Record::VERSION.should match(/\A\d+\.\d+\.\d+\z/)
    end
  end

  describe "UPSTREAM_VERSION" do
    it "records the ported aws-record gem version" do
      Aws::Record::UPSTREAM_VERSION.should eq("2.15.1")
    end
  end
end
