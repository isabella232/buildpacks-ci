#!/usr/bin/env ruby
require 'json'
require 'open-uri'
require 'digest'
require 'net/http'
require 'tmpdir'

$buildpacks_ci_dir = File.expand_path(File.join(File.dirname(__FILE__), '..', '..'))
require_relative "#{$buildpacks_ci_dir}/lib/git-client"

class SourceInput
  attr_reader :name, :url, :version, :md5, :sha256

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
      data.dig('version', 'md5_digest') || '',
      data.dig('version', 'sha256') || ''
    )
  end
end

class BuildInput
  attr_reader :tracker_story_id

  def initialize(tracker_story_id)
    @tracker_story_id = tracker_story_id
  end

  def self.from_file(build_file)
    data = JSON.parse(open(build_file).read)
    BuildInput.new(data.dig('tracker_story_id') || '')
  end

  def copy_to_build_artifacts
    system('rsync -a builds/ builds-artifacts/') or raise('Could not copy builds to builds artifacts')
  end
end


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


class BinaryBuilder
  def build(name, extension_file, old_filename, filename_prefix, ext)
    if $data.dig('version', 'md5_digest')
      digest_arg = "--md5=#{$data.dig('version', 'md5_digest')}"
    elsif $data.dig('version', 'sha256')
      digest_arg = "--sha256=#{$data.dig('version', 'sha256')}"
    else
      digest_arg = "--sha256=" # because php5 doesn't have a sha
    end

    Dir.chdir('binary-builder') do
      if extension_file && extension_file != ""
        run('./bin/binary-builder', "--name=#{name}", "--version=#{source.version}", digest_arg, extension_file)
      else
        run('./bin/binary-builder', "--name=#{name}", "--version=#{source.version}", digest_arg)
      end
    end

    finalize_outputs("binary-builder/#{old_filename}", filename_prefix, ext)
  end
end

def run(*args)
  system({ 'DEBIAN_FRONTEND' => 'noninteractive' }, *args)
  raise "Could not run #{args}" unless $?.success?
end

def finalize_outputs(old_filepath, filename_prefix, ext)
  sha      = Digest::SHA256.hexdigest(open(old_filepath).read)
  filename = "#{filename_prefix}-#{sha[0 .. 7]}.#{ext}"

  FileUtils.mv(old_filepath, "artifacts/#{filename}")
   Dir.mkdir("artifacts")

  {
    sha256: sha,
    url:    "https://buildpacks.cloudfoundry.org/dependencies/#{$name}/#{filename}"
  }
end

def check_sha()
  res = open(source.url).read
  sha = Digest::SHA256.hexdigest(res)
  if $data.dig('version', 'md5_digest') && Digest::MD5.hexdigest(res) != $data.dig('version', 'md5_digest')
    raise "MD5 digest does not match version digest"
  elsif $data.dig('version', 'sha256') && sha != $data.dig('version', 'sha256')
    raise "SHA256 digest does not match version digest"
  end

  [res, sha]
end

def main(binary_builder, stack, source_input, build_input, build_output)
  build_input.copy_to_build_artifacts

  out_data                   = {
    tracker_story_id: build_input.tracker_story_id,
    version:          source_input.version,
    source:           { url: source_input.url }
  }
  out_data[:source][:md5]    = source_input.md5
  out_data[:source][:sha256] = source_input.sha256

  case source_input.name
  when 'bundler'
    out_data.merge!(binary_builder.build("#{source_input.name}", "", "#{source_input.name}-#{source_input.version}.tgz", "#{source_input.name}-#{source_input.version}-#{stack}", 'tgz'))
  when 'hwc'
    out_data.merge!(binary_builder.build('hwc', "", "hwc-#{source_input.version}-windows-amd64.zip", "hwc-#{source_input.version}-windows-amd64", 'zip'))
  when 'dep', 'glide', 'godep'
    out_data.merge!(binary_builder.build("#{source_input.name}", "", "#{source_input.name}-v#{source_input.version}-linux-x64.tgz", "#{source_input.name}-v#{source_input.version}-linux-x64-#{stack}", 'tgz'))
  when 'go'
    out_data.merge!(binary_builder.build('go', "", "go#{source_input.version}.linux-amd64.tar.gz", "go#{source_input.version}.linux-amd64-#{stack}", 'tar.gz'))
  when 'node', 'httpd'
    out_data.merge!(binary_builder.build("#{source_input.name}", "", "#{source_input.name}-#{source_input.version}-linux-x64.tgz", "#{source_input.name}-#{source_input.version}-linux-x64-#{stack}", 'tgz'))
  when 'nginx-static'
    $data['version']['sha256'] = Digest::SHA256.hexdigest(open($data.dig('version', 'url')).read)
    out_data.merge!(binary_builder.build('nginx', "", "nginx-#{source_input.version}-linux-x64.tgz", "nginx-#{source_input.version}-linux-x64-#{stack}", 'tgz'))

  when 'CAAPM', 'appdynamics', 'miniconda2', 'miniconda3'
    results = check_sha()
    out_data.merge!({
      sha256: results[1],
      url:    source_input.url
    })

  when 'setuptools', 'rubygems', 'yarn', 'pip', 'bower'
    results  = check_sha()
    sha      = results[1]
    filename = File.basename(source_input.url).gsub(/(\.(zip|tar\.gz|tar\.xz|tgz))$/, "-#{sha[0 .. 7]}\\1")
    File.write("artifacts/#{filename}", results[0])

    out_data.merge!({
      sha256: sha,
      url:    "https://buildpacks.cloudfoundry.org/dependencies/#{source_input.name}/#{filename}"
    })

  when 'composer'
    out_data.merge!(finalize_outputs("source_input/composer.phar", "composer-#{source_input.version}", 'phar'))

  when 'ruby'
    major, minor, _ = source_input.version.split('.')
    if major == '2' && stack == 'cflinuxfs3' && (minor == '3' || minor == '2')
      run('apt', 'update')
      run('apt-get', 'install', '-y', 'libssl1.0-dev')
    end
    out_data.merge!(binary_builder.build('ruby', "", "ruby-#{source_input.version}-linux-x64.tgz", "ruby-#{source_input.version}-linux-x64-#{stack}", 'tgz'))

  when 'jruby'
    if /9.1.*/ =~ source_input.version
      # jruby 9.1.X.X will implement ruby 2.3.X
      ruby_version = '2.3'
    elsif /9.2.*/ =~ source_input.version
      # jruby 9.2.X.X will implement ruby 2.5.X
      ruby_version = '2.5'
    else
      raise "Unsupported jruby version line #{source_input.version}"
    end
    out_data.merge!(binary_builder.build('jruby', "", "jruby-#{source_input.version}_ruby-#{ruby_version}-linux-x64.tgz", "jruby-#{source_input.version}_ruby-#{ruby_version}-linux-x64-#{stack}", 'tgz'))

  when 'php'
    if source_input.version.start_with?("7")
      phpV = "7"
    elsif source_input.version.start_with?("5")
      phpV = "" # binary-builder expects 'php' to mean php 5.X.
    else
      raise "Unexpected PHP version #{source_input.version}. Expected 5.X or 7.X"
    end

    # add the right extensions
    extension_file = File.join($buildpacks_ci_dir, 'tasks', 'build-binary-new', "php#{phpV}-extensions.yml")
    if source_input.version.start_with?('7.2.')
      extension_file = File.join($buildpacks_ci_dir, 'tasks', 'build-binary-new', "php72-extensions.yml")
    end
    out_data.merge!(binary_builder.build("php#{phpV}", "--php-extensions-file=#{extension_file}", "php#{phpV}-#{source_input.version}-linux-x64.tgz", "php#{phpV}-#{source_input.version}-linux-x64-#{stack}", 'tgz'))

  when 'python'
    major, minor, _ = source_input.version.split('.')
    if major == '3' && minor == '4' && stack == 'cflinuxfs3'
      run('apt', 'update')
      run('apt-get', 'install', '-y', 'libssl1.0-dev')
    end
    out_data.merge!(binary_builder.build('python', '', "python-#{source_input.version}-linux-x64.tgz", "python-#{source_input.version}-linux-x64-#{stack}", 'tgz'))

  when 'pipenv'
    old_filepath = "/tmp/pipenv-v#{source_input.version}.tgz"
    run('apt', 'update')
    run('apt-get', 'install', '-y', 'python-pip', 'python-dev', 'build-essential')
    run('pip', 'install', '--upgrade', 'pip')
    run('pip', 'install', '--upgrade', 'setuptools')
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        run('/usr/local/bin/pip', 'download', '--no-binary', ':all:', "pipenv==#{source_input.version}")
        if Digest::MD5.hexdigest(open("pipenv-#{source_input.version}.tar.gz").read) != $data.dig('version', 'md5_digest')
          raise 'MD5 digest does not match version digest'
        end
        run('/usr/local/bin/pip', 'download', '--no-binary', ':all:', 'pytest-runner')
        run('/usr/local/bin/pip', 'download', '--no-binary', ':all:', 'setuptools_scm')
        run('tar', 'zcvf', old_filepath, '.')
      end
    end
    out_data.merge!(finalize_outputs(old_filepath, "pipenv-v#{source_input.version}-#{stack}", 'tgz'))

  when 'libunwind'
    built_path = File.join(Dir.pwd, 'built')
    Dir.mkdir(built_path)

    Dir.chdir('source_input') do
      # github-releases depwatcher has already downloaded .tar.gz
      run('tar', 'zxf', "libunwind-#{source_input.version}.tar.gz")
      Dir.chdir("libunwind-#{source_input.version}") do
        run('./configure', "--prefix=#{built_path}")
        run('make')
        run('make install')
      end
    end
    old_filename = "libunwind-#{source_input.version}.tgz"
    Dir.chdir(built_path) do
      run('tar', 'czf', old_filename, 'include', 'lib')
    end

    out_data.merge!(finalize_outputs(File.join(built_path, old_filename), "libunwind-#{source_input.version}-#{stack}", 'tar.gz'))

  when 'r'
    artifacts  = "#{Dir.pwd}/artifacts"
    source_sha = ''
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        run('mkdir', '-p', '/usr/share/man/man1')

        run('apt', 'update')

        fs_specific_packages = stack == 'cflinuxfs2' ? ['libgfortran-4.8-dev'] : ['libgfortran-7-dev']
        run('apt-get', 'install', '-y', 'gfortran', 'libbz2-dev', 'liblzma-dev', 'libpcre++-dev', 'libcurl4-openssl-dev', 'default-jre', *fs_specific_packages)

        run('wget', source_input.url)
        source_sha = Digest::SHA256.hexdigest(open("R-#{source_input.version}.tar.gz").read)
        run('tar', 'xf', "R-#{source_input.version}.tar.gz")

        Dir.chdir("R-#{source_input.version}") do
          run('./configure', '--with-readline=no', '--with-x=no', '--enable-R-shlib')
          run('make')
          run('make install')

          run('/usr/local/lib/R/bin/R', '--vanilla', '-e', 'install.packages(c("Rserve","forecast","shiny"), repos="https://cran.r-project.org", dependencies=TRUE)')

          Dir.chdir('/usr/local/lib/R') do
            case stack
            when 'cflinuxfs2'
              run('cp', '-L', '/usr/bin/gfortran-4.8', './bin/gfortran')
              run('cp', '-L', '/usr/lib/gcc/x86_64-linux-gnu/4.8/libcaf_single.a', './lib')
              run('cp', '-L', '/usr/lib/gcc/x86_64-linux-gnu/4.8/libgfortran.a', './lib')
              run('cp', '-L', '/usr/lib/gcc/x86_64-linux-gnu/4.8/libgfortran.so', './lib')
              run('cp', '-L', '/usr/lib/gcc/x86_64-linux-gnu/4.8/libgfortranbegin.a', './lib')
            when 'cflinuxfs3'
              run('cp', '-L', '/usr/bin/x86_64-linux-gnu-gfortran-7', './bin/gfortran')
              run('cp', '-L', '/usr/lib/gcc/x86_64-linux-gnu/7/libcaf_single.a', './lib')
              run('cp', '-L', '/usr/lib/gcc/x86_64-linux-gnu/7/libgfortran.a', './lib')
              run('cp', '-L', '/usr/lib/gcc/x86_64-linux-gnu/7/libgfortran.so', './lib')
            end
            run('tar', 'zcvf', "#{artifacts}/r-v#{source_input.version}.tgz", '.')
          end
        end
      end
    end

    out_data.merge!(finalize_outputs("artifacts/r-v#{source_input.version}.tgz", "r-v#{source_input.version}-#{stack}", 'tgz'))
    out_data[:source_sha256] = source_sha

  when 'nginx'
    artifacts  = "#{Dir.pwd}/artifacts"
    source_pgp = 'not yet implemented'
    destdir    = Dir.mktmpdir
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        run('wget', $data.dig('version', 'url'))
        # TODO validate pgp
        run('tar', 'xf', "nginx-#{source_input.version}.tar.gz")
        Dir.chdir("nginx-#{source_input.version}") do
          run(
            './configure',
            '--prefix=/',
            '--error-log-path=stderr',
            '--with-http_ssl_module',
            '--with-http_realip_module',
            '--with-http_gunzip_module',
            '--with-http_gzip_static_module',
            '--with-http_auth_request_module',
            '--with-http_random_index_module',
            '--with-http_secure_link_module',
            '--with-http_stub_status_module',
            '--without-http_uwsgi_module',
            '--without-http_scgi_module',
            '--with-pcre',
            '--with-pcre-jit',
            '--with-cc-opt=-fPIC -pie',
            '--with-ld-opt=-fPIC -pie -z now',
            '--with-stream=dynamic',
          )
          run('make')
          system({ 'DEBIAN_FRONTEND' => 'noninteractive', 'DESTDIR' => "#{destdir}/nginx" }, 'make install')
          raise "Could not run make install" unless $?.success?

          Dir.chdir(destdir) do
            run('rm', '-Rf', './nginx/html', './nginx/conf')
            run('mkdir', 'nginx/conf')
            run('tar', 'zcvf', "#{artifacts}/nginx-#{source_input.version}.tgz", '.')
          end
        end
      end
    end

    out_data.merge!(finalize_outputs("artifacts/nginx-#{source_input.version}.tgz", "nginx-#{source_input.version}-linux-x64-#{stack}", 'tgz'))
    out_data[:source_pgp] = source_pgp

  when 'dotnet-sdk'
    commit_sha = $data.dig('version', 'git_commit_sha')

    GitClient.clone_repo('https://github.com/dotnet/cli.git', 'cli')

    major, minor, patch = source_input.version.split('.')
    Dir.chdir('cli') do
      GitClient.checkout_branch(commit_sha)
      run('apt-get', 'update')
      run('apt-get', '-y', 'upgrade')
      fs_specific_packages = stack == 'cflinuxfs2' ? ['liburcu1', 'libllvm3.6', 'liblldb-3.6'] : ['liburcu6', 'libllvm3.9', 'liblldb-3.9']
      run('apt-get', '-y', 'install', 'clang', 'devscripts', 'debhelper', 'libunwind8', 'libpython2.7', 'liblttng-ust0', *fs_specific_packages)

      ENV['DropSuffix'] = 'true'
      ENV['TERM']       = 'linux'

      # We must fix the build script for dotnet-sdk versions 2.1.4 to 2.1.2XX (see https://github.com/dotnet/cli/issues/8358)
      if major == '2' && minor == '1' && patch.to_i >= 4 && patch.to_i < 300
        runbuildsh = File.open('run-build.sh', 'r') { |f| f.read }
        runbuildsh.gsub!('WriteDynamicPropsToStaticPropsFiles "${args[@]}"', 'WriteDynamicPropsToStaticPropsFiles')
        File.open('run-build.sh ', 'w') { |f| f.write runbuildsh }
      end

      run('./build.sh', '/t:Compile')
    end

    # The path to the built files changes in dotnet-v2.1.300
    has_artifacts_dir = major.to_i <= 2 && minor.to_i <= 1 && patch.to_i < 300
    old_filepath      = "/tmp/#{source_input.name}.#{source_input.version}.linux-amd64.tar.xz"
    Dir.chdir(if has_artifacts_dir
      Dir['cli/artifacts/*-x64/stage2'][0]
    else
      'cli/bin/2/linux-x64/dotnet'
    end) do
      system('tar', 'Jcf', old_filepath, '.')
    end

    out_data.merge!(finalize_outputs(old_filepath, "#{source_input.name}.#{source_input.version}.linux-amd64-#{stack}", 'tar.xz'))
    out_data.merge!({
      version:        source_input.version,
      git_commit_sha: commit_sha
    })

  else
    raise("Dependency: #{source_input.name} is not currently supported")
  end

  p out_data

  build_output.git_add_and_commit(out_data)
end
