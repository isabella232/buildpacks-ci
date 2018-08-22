require 'json'
require 'open-uri'
require 'digest'
require 'net/http'
require 'tmpdir'

module Runner
  def Runner.run(*args)
    system({ 'DEBIAN_FRONTEND' => 'noninteractive' }, *args)
    raise "Could not run #{args}" unless $?.success?
  end
end

def check_sha(source_input)
  res = open(source_input.url).read
  sha = Digest::SHA256.hexdigest(res)
  if source_input.md5? && Digest::MD5.hexdigest(res) != source_input.md5
    raise 'MD5 digest does not match version digest'
  elsif source_input.sha256? && sha != source_input.sha256
    raise 'SHA256 digest does not match version digest'
  end
  [res, sha]
end

class Builder
  def execute(binary_builder, stack, source_input, build_input, build_output, artifact_output)
    build_input.copy_to_build_output

    out_data                   = {
      tracker_story_id: build_input.tracker_story_id,
      version:          source_input.version,
      source:           { url: source_input.url }
    }
    out_data[:source][:md5]    = source_input.md5 # TODO : fix by not including if null
    out_data[:source][:sha256] = source_input.sha256 # TODO : fix by not including if null

    case source_input.name
    when 'bundler'
      binary_builder.build(source_input)
      out_data.merge!(artifact_output.move_dependency(source_input.name, "#{source_input.name}-#{source_input.version}.tgz", "#{source_input.name}-#{source_input.version}-#{stack}", 'tgz'))

    when 'hwc'
      binary_builder.build(source_input)
      out_data.merge!(artifact_output.move_dependency(source_input.name, "hwc-#{source_input.version}-windows-amd64.zip", "hwc-#{source_input.version}-windows-amd64", 'zip'))

    when 'dep', 'glide', 'godep'
      binary_builder.build(source_input)
      out_data.merge!(artifact_output.move_dependency(source_input.name, "#{source_input.name}-v#{source_input.version}-linux-x64.tgz", "#{source_input.name}-v#{source_input.version}-linux-x64-#{stack}", 'tgz'))

    when 'go'
      binary_builder.build(source_input)
      out_data.merge!(artifact_output.move_dependency(source_input.name, "go#{source_input.version}.linux-amd64.tar.gz", "go#{source_input.version}.linux-amd64-#{stack}", 'tar.gz'))

    when 'node', 'httpd'
      binary_builder.build(source_input)
      out_data.merge!(artifact_output.move_dependency(source_input.name, "#{source_input.name}-#{source_input.version}-linux-x64.tgz", "#{source_input.name}-#{source_input.version}-linux-x64-#{stack}", 'tgz'))

    when 'nginx-static'
      source_input.sha256 = Digest::SHA256.hexdigest(open(source_input.url).read)
      out_data.merge!(artifact_output.move_dependency('nginx', "nginx-#{source_input.version}-linux-x64.tgz", "nginx-#{source_input.version}-linux-x64-#{stack}", 'tgz'))

    when 'CAAPM', 'appdynamics', 'miniconda2', 'miniconda3'
      results           = check_sha(source_input)
      out_data[:sha256] = results[1]
      out_data[:url]    = source_input.url

    when 'setuptools', 'rubygems', 'yarn', 'pip', 'bower' # TODO : fix me
      results  = check_sha(source_input)
      sha      = results[1]
      filename = File.basename(source_input.url).gsub(/(\.(zip|tar\.gz|tar\.xz|tgz))$/, "-#{sha[0..7]}\\1")
      File.write("artifacts/#{filename}", results[0])

      out_data.merge!({
        sha256: sha,
        url:    "https://buildpacks.cloudfoundry.org/dependencies/#{source_input.name}/#{filename}"
      })

    when 'composer'
      out_data.merge!(artifact_output.move_dependency(source_input.name, 'source_input/composer.phar', "composer-#{source_input.version}", 'phar'))

    when 'ruby'
      major, minor, _ = source_input.version.split('.')
      if major == '2' && stack == 'cflinuxfs3' && (minor == '3' || minor == '2')
        Runner.run('apt', 'update')
        Runner.run('apt-get', 'install', '-y', 'libssl1.0-dev')
      end
      binary_builder.build(source_input)
      out_data.merge!(artifact_output.move_dependency('ruby', "ruby-#{source_input.version}-linux-x64.tgz", "ruby-#{source_input.version}-linux-x64-#{stack}", 'tgz'))

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
      binary_builder.build(source_input)
      out_data.merge!(artifact_output.move_dependency('jruby', "jruby-#{source_input.version}_ruby-#{ruby_version}-linux-x64.tgz", "jruby-#{source_input.version}_ruby-#{ruby_version}-linux-x64-#{stack}", 'tgz'))

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
      binary_builder.build(source_input, "--php-extensions-file=#{extension_file}")
      out_data.merge!(artifact_output.move_dependency("php#{phpV}", "php#{phpV}-#{source_input.version}-linux-x64.tgz", "php#{phpV}-#{source_input.version}-linux-x64-#{stack}", 'tgz'))

    when 'python'
      major, minor, _ = source_input.version.split('.')
      if major == '3' && minor == '4' && stack == 'cflinuxfs3'
        Runner.run('apt', 'update')
        Runner.run('apt-get', 'install', '-y', 'libssl1.0-dev')
      end
      binary_builder.build(source_input)
      out_data.merge!(artifact_output.move_dependency('python', "python-#{source_input.version}-linux-x64.tgz", "python-#{source_input.version}-linux-x64-#{stack}", 'tgz'))

    when 'pipenv'
      old_file_path = "/tmp/pipenv-v#{source_input.version}.tgz"
      Runner.run('apt', 'update')
      Runner.run('apt-get', 'install', '-y', 'python-pip', 'python-dev', 'build-essential')
      Runner.run('pip', 'install', '--upgrade', 'pip')
      Runner.run('pip', 'install', '--upgrade', 'setuptools')
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          Runner.run('/usr/local/bin/pip', 'download', '--no-binary', ':all:', "pipenv==#{source_input.version}")
          if Digest::MD5.hexdigest(open("pipenv-#{source_input.version}.tar.gz").read) != source_input.md5
            raise 'MD5 digest does not match version digest'
          end
          Runner.run('/usr/local/bin/pip', 'download', '--no-binary', ':all:', 'pytest-runner')
          Runner.run('/usr/local/bin/pip', 'download', '--no-binary', ':all:', 'setuptools_scm')
          Runner.run('tar', 'zcvf', old_file_path, '.')
        end
      end
      out_data.merge!(artifact_output.move_dependency(source_input.name, old_file_path, "pipenv-v#{source_input.version}-#{stack}", 'tgz'))

    when 'libunwind'
      built_path = File.join(Dir.pwd, 'built')
      Dir.mkdir(built_path)

      Dir.chdir('source') do
        # github-releases depwatcher has already downloaded .tar.gz
        Runner.run('tar', 'zxf', "libunwind-#{source_input.version}.tar.gz")
        Dir.chdir("libunwind-#{source_input.version}") do
          Runner.run('./configure', "--prefix=#{built_path}")
          Runner.run('make')
          Runner.run('make install')
        end
      end
      old_filename = "libunwind-#{source_input.version}.tgz"
      Dir.chdir(built_path) do
        Runner.run('tar', 'czf', old_filename, 'include', 'lib')
      end

      out_data.merge!(artifact_output.move_dependency(source_input.name, File.join(built_path, old_filename), "libunwind-#{source_input.version}-#{stack}", 'tar.gz'))

    when 'r'
      artifacts  = "#{Dir.pwd}/artifacts"
      source_sha = ''
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          Runner.run('mkdir', '-p', '/usr/share/man/man1')

          Runner.run('apt', 'update')

          fs_specific_packages = stack == 'cflinuxfs2' ? ['libgfortran-4.8-dev'] : ['libgfortran-7-dev']
          Runner.run('apt-get', 'install', '-y', 'gfortran', 'libbz2-dev', 'liblzma-dev', 'libpcre++-dev', 'libcurl4-openssl-dev', 'default-jre', *fs_specific_packages)

          Runner.run('wget', source_input.url)
          source_sha = Digest::SHA256.hexdigest(open("R-#{source_input.version}.tar.gz").read)
          Runner.run('tar', 'xf', "R-#{source_input.version}.tar.gz")

          Dir.chdir("R-#{source_input.version}") do
            Runner.run('./configure', '--with-readline=no', '--with-x=no', '--enable-R-shlib')
            Runner.run('make')
            Runner.run('make install')

            Runner.run('/usr/local/lib/R/bin/R', '--vanilla', '-e', 'install.packages(c("Rserve","forecast","shiny"), repos="https://cran.r-project.org", dependencies=TRUE)')

            Dir.chdir('/usr/local/lib/R') do
              case stack
              when 'cflinuxfs2'
                Runner.run('cp', '-L', '/usr/bin/gfortran-4.8', './bin/gfortran')
                Runner.run('cp', '-L', '/usr/lib/gcc/x86_64-linux-gnu/4.8/libcaf_single.a', './lib')
                Runner.run('cp', '-L', '/usr/lib/gcc/x86_64-linux-gnu/4.8/libgfortran.a', './lib')
                Runner.run('cp', '-L', '/usr/lib/gcc/x86_64-linux-gnu/4.8/libgfortran.so', './lib')
                Runner.run('cp', '-L', '/usr/lib/gcc/x86_64-linux-gnu/4.8/libgfortranbegin.a', './lib')
              when 'cflinuxfs3'
                Runner.run('cp', '-L', '/usr/bin/x86_64-linux-gnu-gfortran-7', './bin/gfortran')
                Runner.run('cp', '-L', '/usr/lib/gcc/x86_64-linux-gnu/7/libcaf_single.a', './lib')
                Runner.run('cp', '-L', '/usr/lib/gcc/x86_64-linux-gnu/7/libgfortran.a', './lib')
                Runner.run('cp', '-L', '/usr/lib/gcc/x86_64-linux-gnu/7/libgfortran.so', './lib')
              end
              Runner.run('tar', 'zcvf', "#{artifacts}/r-v#{source_input.version}.tgz", '.')
            end
          end
        end
      end

      out_data.merge!(artifact_output.move_dependency(source_input.name, "artifacts/r-v#{source_input.version}.tgz", "r-v#{source_input.version}-#{stack}", 'tgz'))
      out_data[:source_sha256] = source_sha

    when 'nginx'
      artifacts  = "#{Dir.pwd}/artifacts"
      source_pgp = 'not yet implemented'
      destdir    = Dir.mktmpdir
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          Runner.run('wget', $data.dig('version', 'url'))
          # TODO validate pgp
          Runner.run('tar', 'xf', "nginx-#{source_input.version}.tar.gz")
          Dir.chdir("nginx-#{source_input.version}") do
            Runner.run(
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
            Runner.run('make')
            system({ 'DEBIAN_FRONTEND' => 'noninteractive', 'DESTDIR' => "#{destdir}/nginx" }, 'make install')
            raise 'Could not run make install' unless $?.success?

            Dir.chdir(destdir) do
              Runner.run('rm', '-Rf', './nginx/html', './nginx/conf')
              Runner.run('mkdir', 'nginx/conf')
              Runner.run('tar', 'zcvf', "#{artifacts}/nginx-#{source_input.version}.tgz", '.')
            end
          end
        end
      end

      out_data.merge!(artifact_output.move_dependency(source_input.name, "artifacts/nginx-#{source_input.version}.tgz", "nginx-#{source_input.version}-linux-x64-#{stack}", 'tgz'))
      out_data[:source_pgp] = source_pgp

    when 'dotnet-sdk'
      commit_sha = $data.dig('version', 'git_commit_sha') # TODO : fix

      GitClient.clone_repo('https://github.com/dotnet/cli.git', 'cli')

      major, minor, patch = source_input.version.split('.')
      Dir.chdir('cli') do
        GitClient.checkout_branch(commit_sha)
        Runner.run('apt-get', 'update')
        Runner.run('apt-get', '-y', 'upgrade')
        fs_specific_packages = stack == 'cflinuxfs2' ? ['liburcu1', 'libllvm3.6', 'liblldb-3.6'] : ['liburcu6', 'libllvm3.9', 'liblldb-3.9']
        Runner.run('apt-get', '-y', 'install', 'clang', 'devscripts', 'debhelper', 'libunwind8', 'libpython2.7', 'liblttng-ust0', *fs_specific_packages)

        ENV['DropSuffix'] = 'true'
        ENV['TERM']       = 'linux'

        # We must fix the build script for dotnet-sdk versions 2.1.4 to 2.1.2XX (see https://github.com/dotnet/cli/issues/8358)
        if major == '2' && minor == '1' && patch.to_i >= 4 && patch.to_i < 300
          runbuildsh = File.open('run-build.sh', 'r') { |f| f.read }
          runbuildsh.gsub!('WriteDynamicPropsToStaticPropsFiles "${args[@]}"', 'WriteDynamicPropsToStaticPropsFiles')
          File.open('run-build.sh ', 'w') { |f| f.write runbuildsh }
        end

        Runner.run('./build.sh', '/t:Compile')
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

      out_data.merge!(artifact_output.move_dependency(source_input.name, old_filepath, "#{source_input.name}.#{source_input.version}.linux-amd64-#{stack}", 'tar.xz'))
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
end