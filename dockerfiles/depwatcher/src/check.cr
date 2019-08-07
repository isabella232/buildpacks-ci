# { 
# "source":{"type":"ruby","name":"ruby", "version_filter": "2.4.X"}}
# "version":{"ref":"2.4.5"}
# }


require "./depwatcher/*"
require "json"

data = JSON.parse(STDIN)
STDERR.puts data.to_json
source = data["source"]

case type = source["type"].to_s
when "ruby"
  versions = Depwatcher::Ruby.new.check
end


require "./base"
require "./github_tags"
require "xml"

module Depwatcher
  class Ruby < Base
    class Release
      JSON.mapping(
        ref: String,
        url: String,
        sha256: String,
      )
      def initialize(@ref : String, @url : String, @sha256 : String)
      end
    end

    def check() : Array(Internal)
      name = "ruby/ruby"
      regexp = "^v\\d+_\\d+_\\d+$" # semver
      GithubTags.new(client).matched_tags(name, regexp).map do |r|
        Internal.new(r.name.gsub("_", ".").gsub(/^v/, ""))
      end.sort_by { |i| SemanticVersion.new(i.ref) } # -> [{Comparable semver objects}]
    end

    def in(ref : String) : Release
      releases().select do |r|
        r.ref == ref
      end.first
    end

    private def releases() : Array(Release)
      response = client.get("https://www.ruby-lang.org/en/downloads/").body
      doc = XML.parse_html(response)
      lis = doc.xpath("//li/a[starts-with(text(),'Ruby ')]")
      raise "Could not parse ruby website" unless lis.is_a?(XML::NodeSet)

      lis = lis.reject { |item| item.to_s.includes? "preview" }
      lis = lis.select { |item| item.to_s.match(/\d+/) }

      lis.map do |a|
        parent = a.parent
        version = a.text.gsub(/^Ruby /, "")
        url = a["href"]
        m = /sha256: ([0-9a-f]+)/.match(parent.text) if parent.is_a?(XML::Node)
        sha = m[1] if m
        Release.new(version, url, sha) if url && sha
      end.compact
    end
  end
end


# Filter out irrelevant versions
version_filter = source["version_filter"]?
if version_filter
  filter = SemanticVersionFilter.new(version_filter.to_s)
  versions.select! do |v|
    filter.match(SemanticVersion.new(v.ref))
  end
end

# Filter out versions concourse already knows about
version = data["version"]?
if version
  ref = SemanticVersion.new(version["ref"].to_s) rescue nil
  versions.reject! do |v|
    SemanticVersion.new(v.ref) < ref
  end if ref
end

# output sorted array of versions
puts versions.to_json # [{"ref":"2.4.5"},{"ref":"2.4.6"]

# If there is a discrepency