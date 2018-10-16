class DefaultVersions
  def initialize( manifest, removal_strategy, resource_version, manifest_name)
    @manifest = manifest
    @removal_strategy = removal_strategy
    @resource_version = resource_version
    @manifest_name = manifest_name
  end

  def default_versions
    if @removal_strategy == 'remove_all'
      @manifest['default_versions'] = @manifest['default_versions'].map do |v|
        v['version'] = @resource_version if v['name'] == @manifest_name
        v
      end
    end
  end
end