#!/usr/bin/env ruby
# encoding: utf-8

require 'fileutils'
puts 'yar'
artifact_dir = File.join(Dir.pwd, 'release-artifacts')
release_body_file = File.join(artifact_dir, 'body')
buildpack_repo_dir = 'buildpack'

puts 'yar2'

Dir.chdir(buildpack_repo_dir) do
  go_mod_file = File.file?("go.mod")
  puts 'yar3'
  if go_mod_file
    `go install github.com/cloudfoundry/libcfbuildpack/packager`
    File.write(release_body_file, `packager summary`, mode: 'a')
  end
end
