#!/usr/bin/env ruby
require 'json'
require 'yaml'
require_relative './dependencies'

buildpacks_ci_dir = File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
require_relative "#{buildpacks_ci_dir}/lib/git-client"

manifest = YAML.load_file('buildpack/manifest.yml')
manifest_master = YAML.load_file('buildpack-master/manifest.yml') # rescue { 'dependencies' => [] }

data = JSON.parse(open('source/data.json').read)
name = data.dig('source', 'name')
version = data.dig('version', 'ref')

system('rsync -a buildpack/ artifacts/')
raise('Could not copy buildpack to artifacts') unless $?.success?

added = []
removed = []
rebuilt = []
story_id = JSON.parse(open("builds/binary-builds-new/#{name}/#{version}.json").read)['tracker_story_id']
write_extensions = ''

Dir["builds/binary-builds-new/#{name}/#{version}-*.json"].each do |stack_dependency_build|
  stack = %r{-(.*)\.json$}.match(stack_dependency_build)[1]

  build = JSON.parse(open(stack_dependency_build).read)

  dep = { "name" => name, "version" => version, "uri" => build['url'], "sha256" => build['sha256'], "cf_stacks" => [stack]}

  old_versions = manifest['dependencies'].select { |d| d['name'] == name }.map { |d| {'version' => d['version'], 'stacks' => d['cf_stacks'] } }
  manifest['dependencies'] = Dependencies.new(dep, ENV['VERSION_LINE'], ENV['KEEP_MASTER'], manifest['dependencies'], manifest_master['dependencies']).switch
  new_versions = manifest['dependencies'].select { |d| d['name'] == name }.map { |d| {'version' => d['version'], 'stacks' => d['cf_stacks'] } }

  added += (new_versions - old_versions).uniq.sort
  removed += (old_versions - new_versions).uniq.sort
  rebuilt += old_versions.select {|d| d['version'] && d['stacks'].include?(stack) }

  if added.length == 0 && rebuilt.length == 0
    puts 'SKIP: Built version is not required by buildpack.'
    exit 0
  end
end

### TODO: Figure out when handling deps with multiple stacks
path_to_extensions = 'extensions/appdynamics/extension.py'
if !rebuilt.length && name == 'appdynamics' && manifest['language'] == 'php'
  if removed.length == 1 &&  added.length == 1
    text = File.read('buildpack/' + path_to_extensions)
    write_extensions = text.gsub(/#{Regexp.quote(removed.first)}/, added.first)
  else
    puts 'Expected to have one added version and one removed version for appdynamics in the PHP buildpack.'
    puts 'Got added (#{added}) and removed (#{removed}).'
    exit 1
  end
end

added_stacks = added.map{|d| d['stacks']}.flatten.join(', ')
commit_message = "Add #{name} #{version} for stacks #{added_stacks}"
if rebuilt.length > 0
  rebuilt_stacks = rebuilt.map{|d| d['stacks']}.flatten.join(', ')
  commit_message = "Rebuild #{name} #{version} for stacks #{rebuilt_stacks}"
end
if removed.length > 0
  removed_stacks = removed.map{|d| d['stacks']}.flatten.join(', ')
  commit_message = "#{commit_message}, remove #{name} #{removed.join(', ')} for stacks #{removed_stacks}"
end

Dir.chdir('artifacts') do
  GitClient.set_global_config('user.email', 'cf-buildpacks-eng@pivotal.io')
  GitClient.set_global_config('user.name', 'CF Buildpacks Team CI Server')

  File.write('manifest.yml', manifest.to_yaml)
  GitClient.add_file('manifest.yml')

  if write_extensions != ''
    File.write(path_to_extensions, write_extensions)
    GitClient.add_file(path_to_extensions)
  end

  GitClient.safe_commit("#{commit_message} [##{story_id}]")
end
