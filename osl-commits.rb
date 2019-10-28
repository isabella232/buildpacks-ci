require 'pry'
require 'yaml'
require 'json'

builder_groups = JSON.load(`docker inspect gcr.io/cf-buildpacks/p-cnb-builder@sha256:ceff9ff6206dc542788379495878e4e34385803ba46cdb970d71f00349690067 | jq -r .[].Config.Labels | jq -r '.["io.buildpacks.builder.metadata"]'`)
builder_buildpacks = builder_groups['groups'].flat_map{|group| group['buildpacks']}
builder_cnbs = YAML.load_file('./pipelines/config/cnb-builders.yml')['cnbs']

releases = builder_buildpacks.map do |cnb|
  name = cnb['id'].split('.')
  id = name[0] == "io" ? 'p-'+name[2] : name[2]
  {'id' => id, 'version' => cnb['version']}
end

release_metadata = {}

Dir.mktmpdir do |dir|
  Dir.chdir(dir) do
    release_metadata = releases.map do |release|
      repo = builder_cnbs.dig(release['id'], 'git_repo')
      if !repo
        $STDERR.puts release['id']
        next
      end
      folder = repo.split('/')[-1].gsub('.git','')


      `git clone -q #{repo}`.strip
      commit = ''
      Dir.chdir(folder) do
        version = 'v' + release['version'].delete('v')
        commit = `git rev-list -n 1 #{version}`.strip
      end

      {"release" => folder, 'repo' => repo, 'version' => release['version'], 'commit' => commit}
    end
  end
end

puts release_metadata.to_json
