# encoding: utf-8

require 'tmpdir'
require 'fileutils'
require_relative '../../../tasks/build-binary-new/build.rb'

describe 'BuildInput' do
  let(:build_file) do
    build_json = '{ "tracker_story_id": 159007394 }'
    build_file = File.join(FileUtils.mkdir_p(File.join(Dir.mktmpdir, 'builds', 'binary-builds-new', 'python')), '2.7.14.json')
    File.write(build_file, build_json)
    build_file
  end

  it 'loads from a json file' do
    build_input = BuildInput.from_file(build_file)
    expect(build_input.tracker_story_id).to eq 159007394
  end
end

describe 'SourceInput' do
  let(:source_file) do
    source_json =
      <<~SOURCE_JSON
        {
            "version": {
              "md5_digest": "cee2e4b33ad3750da77b2e85f2f8b724",
              "url": "https://www.python.org/ftp/python/2.7.14/Python-2.7.14.tgz",
              "ref": "2.7.14"
            },
            "source": {
              "version_filter": "2.7.X",
              "type": "python",
              "name": "python"
            }
         }
    SOURCE_JSON
    source_file = File.join(Dir.mktmpdir, 'data.json')
    File.write(source_file, source_json)
    source_file
  end

  it 'loads from a json file' do
    source = SourceInput.from_file(source_file)
    expect(source.name).to eq 'python'
    expect(source.url).to eq 'https://www.python.org/ftp/python/2.7.14/Python-2.7.14.tgz'
    expect(source.version).to eq '2.7.14'
    expect(source.md5).to eq 'cee2e4b33ad3750da77b2e85f2f8b724'
    expect(source.sha256).to eq ''
  end
end

describe 'BuildBinaryNew' do
  context 'when building python' do
    let(:binary_builder) { double(BinaryBuilder) }
    let(:source_input) { SourceInput.new('python', 'https://fake.com', '2.7.14', 'fake-md5', '') }
    let(:build_input) { double(BuildInput) }
    let(:build_output) { double(BuildOutput) }

    it 'returns metadata' do
      expect(binary_builder).to receive(:build)
        .with('python', '', 'python-2.7.14-linux-x64.tgz', 'python-2.7.14-linux-x64-cflinuxfs2', '.tgz')
        .and_return(sha256: 'fake-sha256', url: 'fake-url')

      expect(build_input).to receive(:tracker_story_id).and_return 'fake-story-id'
      expect(build_input).to receive(:copy_to_build_artifacts)

      expect(build_output).to receive(:git_add_and_commit)
        .with({
          :tracker_story_id => "fake-story-id",
          :version          => "2.7.14",
          :source           => { :url => "https://fake.com", :md5 => "fake-md5", :sha256 => "" },
          :sha256           => "fake-sha256",
          :url              => "fake-url"
        })

      main(binary_builder, 'cflinuxfs2', source_input, build_input, build_output)
    end
  end
end


describe 'BinaryBuilder' do
  context 'finalize_outputs' do
    let(:old_filepath) { File.expand_path(File.join(__dir__, '..', '..', 'fixtures', 'build-binary-new', 'python-2.3.tgz')) }
    let(:artifacts_dir) { Dir.mkdir('artifacts') }
    let(:filename_prefix) { 'python-2.3-cflinuxfs3' }
    let(:ext) { 'tgz' }

    before do
      system("touch #{old_filepath}")
    end

    it 'outputs the correct sha and URL' do
      expect(finalize_outputs(old_filepath, filename_prefix, ext)).to eq(
        sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        url:    'https://buildpacks.cloudfoundry.org/dependencies//python-2.3-cflinuxfs3-e3b0c442.tgz'
      )
    end
    after do
      FileUtils.rm_rf('artifacts')
    end
  end

  # context 'build' do
  #   expect(binary)
  # end
end
