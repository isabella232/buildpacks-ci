$buildpacks_ci_dir = File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
require_relative "#{$buildpacks_ci_dir}/lib/git-client"

class BuildOutput
  def initialize(name, version, stack, tracker_story_id)
    @name             = name
    @version          = version
    @stack            = stack
    @tracker_story_id = tracker_story_id
  end

  def git_add_and_commit(out_data)
    Dir.chdir('builds-artifacts') do
      GitClient.set_global_config('user.email', 'cf-buildpacks-eng@pivotal.io')
      GitClient.set_global_config('user.name', 'CF Buildpacks Team CI Server')

      out_file = File.join('binary-builds-new', @name, "#{@version}-#{@stack}.json")
      File.write(out_file, out_data.to_json)

      GitClient.add_file(out_file)
      GitClient.safe_commit("Build #{@name} - #{@version} - #{@stack} [##{@tracker_story_id}]")
    end
  end
end