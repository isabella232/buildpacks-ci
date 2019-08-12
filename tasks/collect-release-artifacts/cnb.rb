require 'octokit'

class CNB
  attr_accessor :name, :version, :url

  def initialize(id, current_version, version_diff, oktokit = Octokit)
    set_name_and_url(id)
    @version = current_version
    @version_diff = version_diff
    @oktokit = oktokit
  end

  def release_notes
    if first?
      "### Added version #{@version}"
    else
      release_notes_map = releases.map do | release |
        trimmed_release_notes = clean_release_notes(release.body)
        more_details          = "More details are [here](#{release.html_url})."
        "### #{release.name}\n#{trimmed_release_notes}\n\n#{more_details}\n"
      end
      release_notes_map.join("\n")
    end
  end

  private

  def first?
    @version_diff.first == "new-cnb"
  end

  def releases
    @releases ||= @oktokit.releases(@url).select{|release| @version_diff.include? release.tag_name}
  end

  def set_name_and_url(id)
    cnb_name = id.split('.').last
    if id.start_with? "org.cloudfoundry"
      name = "#{cnb_name}-cnb"
      url = "cloudfoundry/#{name}"
    elsif id.start_with? "io.pivotal"
      name = "p-#{cnb_name}-cnb"
      url = "pivotal-cf/#{name}"
    elsif id.start_with? "lifecycle"
      name = id
      url = "buildpack/#{name}"
    else
      raise "unknown cnb path"
    end

    @name = name
    @url = url
  end

  def clean_release_notes(release_body)
    if release_body.include? "No major changes"
      return ""
    end
    stripped_release_body = release_body.split('Packaged binaries:')[0]
    stripped_release_body.split('Supported stacks:')[0].strip
  end

end

# Template.do([cnb, cnb])
# # @cnb.new(cnb,versions, version_diff)
#         # @cnb.intro
#         # @cnb.release_notes => "Release notes for NAME:\nnote2note12"
#
#
#         cnb_release_note = ""
#         name, url        = cnb_name_and_url(cnb)
#         cnb_release_note << "\n## #{name} \n"
#
#         if versions.first == 'new-cnb'
#           cnb_release_note << "### Added version #{versions.last}\n"
#         else
#           releases = Octokit.releases(url).select { |release| versions.include? release.tag_name }
#           releases.each_with_index do |release, index|
#             if index == 0
#               # Add binaries and stack information before any version specific release notes
#               cnb_release_note << "#{binaries_and_stacks_for_cnb(release.body)}\n"
#             end
#             trimmed_release_notes = clean_release_notes(release.body)
#             more_details          = "More details are [here](#{release.html_url})."
#             cnb_release_note << "### #{release.name}\n#{trimmed_release_notes}\n\n#{more_details}\n"
#           end
#         end
#
#         return cnb_release_note
#       end