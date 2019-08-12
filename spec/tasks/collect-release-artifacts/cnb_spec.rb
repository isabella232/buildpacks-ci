require_relative '../../../tasks/collect-release-artifacts/cnb'

describe CNB do
  describe "#dependencies"
  describe "#stacks"
  describe "#release_notes" do
    it "is a cnb which has just been added to the shim" do
      cnb = CNB.new("org.cloudfoundry.nodejs", "1", ["new-cnb", "1"])

      expected_notes = "### Added version 1"
      expect(cnb.release_notes).to eq(expected_notes)
    end

    it "is an updated existing dependency with one update" do
      octokit = double("Octokit")
      release_object = OpenStruct.new(
        :name => "v2",
        :tag_name => "v2",
        :body => "somebody",
        :html_url => "http://foo.gov"
      )
      expect(octokit).to receive(:releases).with("pivotal-cf/p-snyk-cnb")
        .and_return([release_object])

      cnb = CNB.new("io.pivotal.snyk", "v2", ["v2"], octokit)

      expected_notes = <<~NOTES
### v2
somebody

More details are [here](http://foo.gov).
      NOTES

      expect(cnb.release_notes).to eq(expected_notes)
    end

    it "is an updated existing dependency with multiple update" do
      octokit = double("Octokit")
      release_object_v2 = OpenStruct.new(
        :name => "v2",
        :tag_name => "v2",
        :body => "somebody",
        :html_url => "http://foo.gov"
      )
      release_object_v1 = OpenStruct.new(
        :name => "v1",
        :tag_name => "v1",
        :body => "somebody",
        :html_url => "http://foo.gov"
      )
      expect(octokit).to receive(:releases).with("pivotal-cf/p-snyk-cnb")
        .and_return([release_object_v2, release_object_v1])

      cnb = CNB.new("io.pivotal.snyk", "v2", ["v2", "v1"], octokit)

      expected_notes = <<~NOTES
### v2
somebody

More details are [here](http://foo.gov).

### v1
somebody

More details are [here](http://foo.gov).
      NOTES

      expect(cnb.release_notes).to eq(expected_notes)
    end
  end
end

## NodeJs
# Packaged dependencies:
# ...
# Supported Stacks:
# ...
### Added version v0.0.1
#
### 2
# somebody

