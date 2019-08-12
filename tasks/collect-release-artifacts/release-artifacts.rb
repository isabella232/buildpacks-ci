#!/usr/bin/env ruby

require 'octokit'
require 'yaml'
require 'rubygems'
require 'zip'
require 'digest'
require 'fileutils'

class ReleaseArtifacts
  class << self
    def download_latest_release(repo, octokit = Octokit)
      repo_url = "cloudfoundry/#{repo}"
      unless octokit.releases(repo_url) == []
        latest_url = octokit.latest_release(repo_url).zipball_url
        path       = "source.zip"
        `wget -O #{path} #{latest_url}`
        path
      end
    end

    def open_manifest_from_zip(path)
      manifest = ""
      Zip::File.open(path) do |zip_file|
        entry = zip_file.glob('{*/,}manifest.yml').first
        unless entry.nil?
          manifest = YAML.load(entry.get_input_stream.read)
        end
      end
      manifest
    end

    def reduce_manifest(manifest)
      manifest.fetch('dependencies').reduce({}) do |accumulator, dep|
        accumulator[dep['name']] = dep['version']
        accumulator
      end
    end

    def cnb_name_and_url(name)
      cnb_name = name.split('.').last
      url      = ""
      if name.start_with? "org.cloudfoundry"
        name = "#{cnb_name}-cnb"
        url  = "cloudfoundry/#{name}"
      elsif name.start_with? "io.pivotal"
        name = "p-#{cnb_name}-cnb"
        url "pivotal-cf/#{name}"
      elsif name.start_with? "lifecycle"
        url = "buildpack/#{name}"
      else
        raise "unknown cnb path"
      end
      [name, url]
    end

    def find_version_diffs(old_deps, new_deps, octokit = Octokit)
      cnb_version_map = {}
      new_deps.each do |dep, version|
        if old_deps.include? dep
          old_version = old_deps[dep]
          _, url      = cnb_name_and_url(dep)
          cnb_tags    = octokit.tags(url).collect { |tag| tag.name }
          # Get the releases in between the last and the current, inclusive of the current release
          diff_version         = cnb_tags[cnb_tags.index("v#{version}")...cnb_tags.index("v#{old_version}")]
          cnb_version_map[dep] = diff_version
        else
          cnb_version_map[dep] = ['new-cnb', "v#{version}"]
        end
      end
      cnb_version_map
    end

    def clean_release_notes(release_body)
      if release_body.include? "No major changes"
        return ""
      end
      stripped_release_body = release_body.split('Packaged binaries:')[0]
      stripped_release_body.split('Supported stacks:')[0].strip!
    end

    def binaries_and_stacks_for_cnb(release)
      idx = release.index("Packaged binaries") || 0
      if idx == 0
        idx = release.index("Supported stacks") || release.length
      end
      # Returns substring from that index until the end
      release[idx..-1]
    end

# Consider using a markdown gem and/or templating for this.
    def compile_release_notes(repo, tag, cnb_version_diff)
      intro_release_notes = "# #{repo} #{tag} \nBelow are the release notes for:\n"

      cnb_release_notes = cnb_version_diff.map do |cnb, versions| #
        # @cnb.new(cnb,versions, version_diff)
        # @cnb.intro
        # @cnb.release_notes => "Release notes for NAME:\nnote2note12"


        cnb_release_note = ""
        name, url        = cnb_name_and_url(cnb)
        intro_release_notes << "\n* #{name} "
        cnb_release_note << "\n## #{name} \n"

        if versions.first == 'new-cnb'
          cnb_release_note << "### Added version #{versions.last}\n"
        else
          releases = Octokit.releases(url).select { |release| versions.include? release.tag_name }
          releases.each_with_index do |release, index|
            if index == 0
              # Add binaries and stack information before any version specific release notes
              cnb_release_note << "#{binaries_and_stacks_for_cnb(release.body)}\n"
            end
            trimmed_release_notes = clean_release_notes(release.body)
            more_details          = "More details are [here](#{release.html_url})."
            cnb_release_note << "### #{release.name}\n#{trimmed_release_notes}\n\n#{more_details}\n"
          end
        end

        return cnb_release_note
      end

      intro_release_notes + cnb_release_notes
    end
  end
end