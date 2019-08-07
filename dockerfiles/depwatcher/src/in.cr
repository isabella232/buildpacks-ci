# { 
# "source":{"type":"ruby","name":"ruby", "version_filter": "2.4.X"}}
# "version":{"ref":"2.4.6"}
# }
require "./depwatcher/*"
require "json"

dir = ARGV[0]
data = JSON.parse(STDIN)
STDERR.puts data.to_json
source = data["source"]
version = data["version"]

case type = source["type"].to_s
when "ruby"
  version = Depwatcher::Ruby.new.in(version["ref"].to_s)
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
      regexp = "^v\\d+_\\d+_\\d+$"
      GithubTags.new(client).matched_tags(name, regexp).map do |r|
        Internal.new(r.name.gsub("_", ".").gsub(/^v/, ""))
      end.sort_by { |i| SemanticVersion.new(i.ref) }
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


if version
  File.write("#{dir}/data.json", { source: source, version: version }.to_json)
  STDERR.puts version.to_json
  puts({ version: data["version"] }.to_json)
else
  raise "Unable to retrieve version:\n#{data}"
end

