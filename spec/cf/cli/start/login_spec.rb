require "spec_helper"

describe CF::Start::Login do
  let(:client) { build(:client) }

  describe "metadata" do
    before do
      stub_client_and_precondition
    end

    let(:command) { Mothership.commands[:login] }

    describe "command" do
      subject { command }
      its(:description) { should eq "Authenticate with the target" }
      specify { expect(Mothership::Help.group(:start)).to include(subject) }
    end

    include_examples "inputs must have descriptions"

    describe "flags" do
      subject { command.flags }

      its(["-o"]) { should eq :organization }
      its(["--org"]) { should eq :organization }
      its(["--email"]) { should eq :username }
      its(["-s"]) { should eq :space }
    end

    describe "arguments" do
      subject(:arguments) { command.arguments }
      it "have the correct commands" do
        expect(arguments).to eq [{:type => :optional, :value => :email, :name => :username}]
      end
    end
  end

  describe "running the command" do
    before do
      stub_client
    end

    stub_home_dir_with { "#{SPEC_ROOT}/fixtures/fake_home_dirs/new" }

    let(:auth_token) { CFoundry::AuthToken.new("bearer some-new-access-token", "some-new-refresh-token") }
    let(:tokens_yaml) { YAML.load_file(File.expand_path(tokens_file_path)) }
    let(:tokens_file_path) { "~/.cf/tokens.yml" }

    before do
      client.stub(:login).with("my-username", "my-password") { auth_token }
      client.stub(:login_prompts).and_return(
      {
        :username => ["text", "Username"],
        :password => ["password", "8-digit PIN"]
      })

      stub_ask("Username", {}) { "my-username" }
      stub_ask("8-digit PIN", {:echo => "*", :forget => true}) { "my-password" }
    end

    subject { cf ["login"] }

    context "when there is a target" do
      before do
        CF::Populators::Target.any_instance.stub(:populate_and_save!)
        stub_precondition
      end

      it "logs in with the provided credentials and saves the token data to the YAML file" do
        subject

        expect(tokens_yaml["https://api.some-domain.com"][:token]).to eq("bearer some-new-access-token")
        expect(tokens_yaml["https://api.some-domain.com"][:refresh_token]).to eq("some-new-refresh-token")
      end

      it "calls use a PopulateTarget to ensure that an organization and space is set" do
        CF::Populators::Target.should_receive(:new) { double(:target, :populate_and_save! => true) }
        subject
      end

      context "when the user logs in with invalid credentials" do
        before do
          client.should_receive(:login).with("my-username", "my-password").and_raise(CFoundry::Denied)
        end

        it "informs the user gracefully" do
          subject
          expect(output).to say("Authenticating... FAILED")
        end
      end
    end

    context "when there is no target" do
      it "tells the user to select a target" do
        client.stub(:target) { nil }
        subject
        expect(error_output).to say("Please select a target with 'cf target'.")
      end
    end
  end
end
