# encoding: utf-8
require 'tracker_api'
require 'yaml'

class BuildpackReleaseStoryCreator
  attr_reader :buildpack_name, :previous_buildpack_version,
              :tracker_requester_id, :buildpack_project, :buildpack_releng_project, :old_manifest, :new_manifest

  def initialize(buildpack_name:, previous_buildpack_version:, tracker_project_id:, releng_tracker_project_id:,
                 tracker_requester_id:, tracker_api_token:, old_manifest:, new_manifest:)
    @buildpack_name = buildpack_name
    @previous_buildpack_version = previous_buildpack_version
    @tracker_requester_id = tracker_requester_id

    tracker_client = TrackerApi::Client.new(token: tracker_api_token)
    @buildpack_project = tracker_client.project(tracker_project_id)
    @buildpack_releng_project = tracker_client.project(releng_tracker_project_id)
    @old_manifest = old_manifest
    @new_manifest = new_manifest
  end

  def run!
    story_name = "**Release:** #{buildpack_name}-buildpack #{new_release_version}"

    story_description = stories_since_last_release.inject("Stories:\n\n") do |story_text, story|
      story_text + "##{story.id} - #{story.name}\n"
    end
    story_description += "\n**Dependency Changes:**\n\n"
    story_description += generate_dependency_changes
    story_description += "\nRefer to [release instructions](https://docs.cloudfoundry.org/buildpacks/releasing_a_new_buildpack_version.html).\n"

    story = buildpack_project.create_story(
      name: story_name,
      description: story_description,
      estimate: 0,
      labels: [buildpack_name, 'release'],
      requested_by_id: tracker_requester_id
    )
    commit_msg = "git ci -m \"Bump version to $(cat VERSION) [##{story.id}]\""
    story.description = story_description + "\n**Commit Message**\n```\n#{commit_msg}\n```"
    story.save

    story
  end

  def stories_since_last_release
    story_id = most_recent_release_story_id
    all = [
        buildpack_project.stories(filter: "(label:#{buildpack_name} OR label:#{buildpack_name}-buildpack OR label:all) AND (accepted_after:09/24/2015 OR -state:accepted)", limit: 1000, auto_paginate: true), #accepted_after is because the api was returning very old stories at the wrong indexes
        buildpack_releng_project.stories(filter: "(label:#{buildpack_name} OR label:#{buildpack_name}-buildpack OR label:all) AND (accepted_after:09/24/2015 OR -state:accepted)", limit: 1000, auto_paginate: true) #accepted_after is because the api was returning very old stories at the wrong indexes
    ].flatten
    all.sort! {|a,b| a.id <=> b.id}
    idx = all.find_index{ |s| s.id == story_id } if story_id
    idx ? all[(idx+1)..-1] : all
  end

  def most_recent_release_story_id
    story = buildpack_project.stories(filter: "label:release AND label:#{buildpack_name} AND -state:unscheduled").last
    story.id if story
  end

  def new_release_version
    @previous_buildpack_version.split('.').tap do |arr|
      arr[-1].succ!
    end.join('.')
  end

  def get_added_versions(new_deps, old_deps, name)
    ((new_deps[name] || []) - (old_deps[name] || [])).uniq.sort
  end

  def get_removed_versions(new_deps, old_deps, name)
    ((old_deps[name] || []) - (new_deps[name] || [])).uniq.sort
  end

  def generate_dependency_changes
    new_dependencies = YAML.load(@new_manifest)['dependencies'].each_with_object({}) do |dep, h|
      if h.key?(dep['name'])
        h[dep['name']].push(dep['version'])
      else
        h[dep['name']] = [dep['version']]
      end
    end
    old_dependencies = YAML.load(@old_manifest)['dependencies'].each_with_object({}) do |dep, h|
      if h.key?(dep['name'])
        h[dep['name']].push(dep['version'])
      else
        h[dep['name']] = [dep['version']]
      end
    end

    description = "```\n"

    new_dependencies.each_key do |name|
      added_versions = get_added_versions(new_dependencies, old_dependencies, name)
      removed_versions = get_removed_versions(new_dependencies, old_dependencies, name)
      if !added_versions.empty? && !removed_versions.empty?
        description += "#{name}: #{removed_versions.join(', ')} -> #{added_versions.join(', ')}\n"
      end
    end
    new_dependencies.each_key do |name|
      added_versions = get_added_versions(new_dependencies, old_dependencies, name)
      removed_versions = get_removed_versions(new_dependencies, old_dependencies, name)
      if !added_versions.empty? && removed_versions.empty?
        description += "+ #{name}: #{added_versions.join(', ')}\n"
      end
    end
    old_dependencies.each_key do |name|
      added_versions = get_added_versions(new_dependencies, old_dependencies, name)
      removed_versions = get_removed_versions(new_dependencies, old_dependencies, name)
      if added_versions.empty? && !removed_versions.empty?
        description += "- #{name}: #{removed_versions.join(', ')}\n"
      end
    end
    description += "```\n"
  end
end
