class SourceInput
  attr_reader :name, :url, :version, :md5
  attr_accessor :sha256

  def initialize(name, url, version, md5, sha256)
    @name    = name
    @url     = url
    @version = version
    @md5     = md5
    @sha256  = sha256
  end

  def self.from_file(source_file)
    data = JSON.parse(open(source_file).read)
    SourceInput.new(
      data.dig('source', 'name') || '',
      data.dig('version', 'url') || '',
      data.dig('version', 'ref') || '',
      data.dig('version', 'md5_digest'),
      data.dig('version', 'sha256')
    )
  end

  def md5?
    !@md5.nil?
  end

  def sha256?
    !@sha256.nil?
  end
end