#!/usr/bin/env ruby
require 'open-uri'
require 'digest'
require_relative '../build-binary-new/source_input'
require_relative '../build-binary-new/build_input'
require_relative '../build-binary-new/build_output'

def get_sha_from_text_file(url)
  open(url).read.match(/^(.*) .*linux-x64.tar.gz$/).captures.first.strip
end

dep = ENV['DEP']


source_input    = SourceInput.from_file('source/data.json')
build_input     = BuildInput.from_file("builds/binary-builds-new/#{source_input.name}/#{source_input.version}.json")
build_output    = BuildOutput.new(source_input.name)
build_input.copy_to_build_output
sha256 = ''
url = ''
if dep == 'node':
  url = "https://nodejs.org/dist/v#{source_input.version}/node-v#{source_input.version}-linux-x64.tar.gz"
  sha256 = get_sha_from_text_file("https://nodejs.org/dist/v#{source_input.version}/SHASUMS256.txt"),
elsif dep == 'icu' #TODO make this work
  url = "https://github.com/#{source_input.repo}/releases/download/#{source_input.version}/something.tgz" #TODO fix this
  filename = "icu.tgz"
  dir = Dir.mktmpdir
  keys = "https://ssl.icu-project.org/KEYS"

  Dir.chdir(dir) do
    `wget #{keys}`
    `wget #{url} -O #{filename}`
    `wget #{url}.asc -O #{filename}.asc`
    `gpg --import KEYS`
    resp = `gpg --verify .asc file`
    if resp.include? "Good signature from"
      sha256 = Digest::SHA256.file(filename).hexdigest
    elsif
      raise "Can't verify #{url}'s pgp signature"
    end
  end
else
  raise "Unknown dependency"
end

build_output.add_output("#{source_input.version}-bionic.json",
  {
    sha256: sha256
    url: url
  }
)

build_output.commit_outputs("Build #{source_input.name} - #{source_input.version} - io.buildpacks.stacks.bionic [##{build_input.tracker_story_id}]")
