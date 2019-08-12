require 'yaml'
require "ostruct"

require_relative '../../../tasks/collect-release-artifacts/release-artifacts'

describe ReleaseArtifacts do
  ci_path = File.dirname(__FILE__ )
  fixtures_path = File.expand_path(File.join(ci_path, "..", "..","fixtures", "collect-release-artifacts"))

  before do
    ENV.store('REPO', "nodejs-cnb")
    ENV.store('STACK', "")
    ENV.store('GITHUB_ACCESS_TOKEN', '')
  end

  after do
  end

  context '#reduce_manifest' do
    it 'collects all versions for every dependency' do
      manifest = YAML.load_file(File.join(fixtures_path, "manifest.yml"))
      expected_deps = {"org.cloudfoundry.node-engine" => "0.0.27",
      "org.cloudfoundry.nodejs-compat" => "0.0.7"}
      expect(ReleaseArtifacts.reduce_manifest(manifest)).to eq(expected_deps)
    end
  end

  context '#find_version_diffs' do
    before(:each) do
      @octokit = double("Octokit")
      @old_deps = {"org.cloudfoundry.node-engine" => "0.0.25",
        "org.cloudfoundry.nodejs-compat" => "0.0.4"}
      @new_deps = {"org.cloudfoundry.node-engine" => "0.0.27",
        "org.cloudfoundry.nodejs-compat" => "0.0.7"}
      @expected_diff = {
        "org.cloudfoundry.node-engine" => %w(v0.0.27 v0.0.26),
        "org.cloudfoundry.nodejs-compat" => %w(v0.0.7 v0.0.6 v0.0.5)
      }
    end

    it 'requests latest releases' do
      node_engine_versions = %w(v0.0.27 v0.0.26 v0.0.25 v0.0.24 v0.0.23)
      nodejs_compat_versions = %w(v0.0.7 v0.0.6 v0.0.5 v0.0.4 v0.0.3)
      expect(@octokit).to receive(:tags).with("cloudfoundry/node-engine-cnb").and_return(node_engine_versions.map{|v| OpenStruct.new(:name => v)})
      expect(@octokit).to receive(:tags).with("cloudfoundry/nodejs-compat-cnb").and_return(nodejs_compat_versions.map{|v| OpenStruct.new(:name => v)})
      expect(ReleaseArtifacts.find_version_diffs(@old_deps, @new_deps, @octokit)).to eq(@expected_diff)
    end

    it "doesn't request latest releases" do
      node_engine_versions = %w(v0.0.28 v0.0.27 v0.0.26 v0.0.25 v0.0.24 v0.0.23)
      nodejs_compat_versions = %w(v0.0.8 v0.0.7 v0.0.6 v0.0.5 v0.0.4 v0.0.3)
      expect(@octokit).to receive(:tags).with("cloudfoundry/node-engine-cnb").and_return(node_engine_versions.map{|v| OpenStruct.new(:name => v)})
      expect(@octokit).to receive(:tags).with("cloudfoundry/nodejs-compat-cnb").and_return(nodejs_compat_versions.map{|v| OpenStruct.new(:name => v)})
      expect(ReleaseArtifacts.find_version_diffs(@old_deps, @new_deps, @octokit)).to eq(@expected_diff)
    end

    it "is in the new deps but not in the old deps" do
      node_engine_versions = %w(v0.0.27 v0.0.26 v0.0.25 v0.0.24 v0.0.23)
      expect(@octokit).to receive(:tags).with("cloudfoundry/node-engine-cnb").and_return(node_engine_versions.map{|v| OpenStruct.new(:name => v)})
      old_deps = {"org.cloudfoundry.node-engine" => "0.0.25", }
      expected_diff = {
        "org.cloudfoundry.node-engine" => %w(v0.0.27 v0.0.26),
        "org.cloudfoundry.nodejs-compat" => %w(new-cnb v0.0.7)
      }
      expect(ReleaseArtifacts.find_version_diffs(old_deps, @new_deps, @octokit)).to eq(expected_diff)

    end

    it "is in the old deps but not in the new deps" do
      node_engine_versions = %w(v0.0.27 v0.0.26 v0.0.25 v0.0.24 v0.0.23)
      expect(@octokit).to receive(:tags).with("cloudfoundry/node-engine-cnb").and_return(node_engine_versions.map{|v| OpenStruct.new(:name => v)})
      new_deps = {"org.cloudfoundry.node-engine" => "0.0.27",}
      expected_diff = {
        "org.cloudfoundry.node-engine" => %w(v0.0.27 v0.0.26),
      }
      expect(ReleaseArtifacts.find_version_diffs(@old_deps, new_deps, @octokit)).to eq(expected_diff)
    end
  end

  context '#compile_release_notes' do

  end
end
