#! /usr/bin/env ruby

# Copyright 2019, Erich Cernaj
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'tmpdir'
require 'optparse'
require 'bundler'
require 'open3'

def check_file(path, name)
  return if File.file?(path)

  STDERR.puts "Couldn't find #{name}"
  exit 1
end

# Install fpm to build_dir/fpm unless it's already installed
# Set GEM_PATH and GEM_HOME to build_dir/gems
# Return path to fpm
def setup_fpm(build_dir)
  FileUtils.mkdir_p(build_dir) unless File.exist?(build_dir)
  ENV['GEM_PATH'] = "#{build_dir}/fpm:#{build_dir}/gems"
  ENV['GEM_HOME'] = "#{build_dir}/fpm"
  _, _, status = Open3.capture3('gem', 'list',
                                '-i', 'fpm')
  unless status.success?
    STDERR.puts 'Installing fpm'
    fpm_install = 'gem',
                  'install',
                  '--no-ri',
                  '--no-rdoc',
                  'fpm'
    run_command(fpm_install)
  end
  ENV['GEM_HOME'] = "#{build_dir}/gems"
  "#{build_dir}/fpm/bin/fpm"
end

# Copy lockfile and gemfile to temporary dir
# Parse lockfile and return Bundler::LockfileParser
def parse_lockfile(lockfile, gemfile)
  temp_dir = Dir.mktmpdir
  check_file(lockfile, 'lockfile (-l PATH)')
  FileUtils.cp(lockfile, "#{temp_dir}/Gemfile.lock")
  check_file(gemfile, 'gemfile (-g PATH)')
  FileUtils.cp(gemfile, "#{temp_dir}/Gemfile")

  STDERR.puts 'Parsing Lockfile'
  gems = nil
  Dir.chdir(temp_dir) do
    begin
      gems = Bundler::LockfileParser.new(Bundler.read_file('Gemfile.lock'))
    rescue LockfileError => e
      STDERR.puts 'Error parsing lockfile'
      STDERR.puts e.message
    end
  end
  gems
end

# Take Bundler::LockfileParser and return gems, versions and dependencies
def get_gems_from_lockfile(lockfile)
  gems = {}
  lockfile.specs.each do |gem|
    gem_name = gem.name
    gems[[gem_name, gem.version.to_s]] = []
    gem.dependencies.each do |dependency|
      gems[[gem_name, gem.version.to_s]].push(dependency.name)
    end
  end
  gems
end

# Sort gems with topological sort
def sort_gems(gems)
  output = {}
  STDERR.puts 'Sorting gems'
  until gems.empty?
    gems.each do |gem, dependencies|
      next if (output.empty? && !dependencies.empty?) ||
              !dependencies.all? do |dependency|
                output.any? do |installed_gem, _version|
                  installed_gem == dependency
                end
              end

      output[gem[0]] = gem[1]
      gems.delete(gem)
    end
  end
  output
end

# Return only chosen_gems from all_gems
def choose_gems(all_gems, chosen_gems)
  output = {}
  all_gems.each do |name, version|
    if chosen_gems.include?(name)
      output[name] = version
      chosen_gems.delete(name)
    end
  end
  unless chosen_gems.empty?
    STDERR.puts "Couldn't include these gems:"
    chosen_gems.each { |gem| STDERR.puts gem }
  end
  output
end

# Return all_gems - excluded_gems
def exclude_gems(all_gems, excluded_gems)
  output = {}
  all_gems.each do |name, version|
    output[name] = version unless excluded_gems.include?(name)
  end
  output
end

# Run command with Open3
# Return exit status, stdout
def run_command(command)
  stdout, stderr, status = Open3.capture3(*command)
  unless status.success?
    STDERR.puts("Error executing command:\n#{command.join(' ')}")
    STDERR.puts(stderr)
    return false, nil
  end
  [true, stdout]
end

# Return true if package was created
def package_exists?(gem)
  prefix = "#{gem[:package_location]}/#{gem[:name_prefix]}-"
  # deb can't have _ in name and for rpm it's changed to -
  name = gem[:name].tr('_', '-')

  if Dir.glob("#{prefix}#{name}{-,_}#{gem[:version]}*.#{gem[:type]}").any?
    STDERR.puts "#{gem[:name]} is already created"
    return true
  end
  false
end

# Create package for gem with fpm
def pack_gem(gem, build_dir, fpm_path)
  return 0 if package_exists?(gem)

  STDERR.puts "Creating #{gem[:name]} #{gem[:version]}"
  # install gem to build_dir to setup dependencies for other gems
  gem_install_command = 'gem',
                        'install',
                        '--install-dir', "#{build_dir}/gems",
                        '--ignore-dependencies',
                        '--no-ri',
                        '--no-rdoc',
                        '-f',
                        '-v', gem[:version],
                        gem[:name]
  fpm_command = fpm_path,
                '-s', 'gem',
                '-t', gem[:type],
                '-p', gem[:package_location],
                '--deb-no-default-config-files',
                '--deb-ignore-iteration-in-dependencies',
                '--rpm-ignore-iteration-in-dependencies',
                '--prefix', gem[:install_location],
                '--gem-bin-path', gem[:bin_path],
                '--gem-package-name-prefix', gem[:name_prefix],
                '--name', "#{gem[:name_prefix]}-#{gem[:name].tr('_', '-')}",
                '-m', gem[:packager],
                '--iteration', gem[:release_num].to_s,
                "#{build_dir}/gems/cache/#{gem[:name]}-#{gem[:version]}.gem"

  gem_install, = run_command(gem_install_command)
  unless gem_install
    STDERR.puts "Couldn't build package #{gem[:name]} #{gem[:version]}"
    exit 1
  end

  fpm, fpm_output = run_command(fpm_command)
  unless fpm
    STDERR.puts "Couldn't build package #{gem[:name]} #{gem[:version]}"
    exit 1
  end

  # fpm returns hash with path to created package
  package_name = /:path=>"(.*)"/.match(fpm_output).captures[0]
  STDERR.puts "Created package #{package_name}"
  0
end

ARGV << '-h' if ARGV.empty?

options = {}
optparser = OptionParser.new do |opts|
  options[:packageType] = nil
  opts.on('-t', '--packagetype TYPE',
          'Type of created packages (deb, rpm)') do |type|
    options[:packageType] = type
  end
  options[:lockfilePath] = '/usr/share/one/Gemfile.lock'
  opts.on('-l', '--lockfilepath PATH',
          'Path to lockfile (default: /usr/share/one/Gemfile.lock)') do |path|
    options[:lockfilePath] = path
  end
  options[:gemfilePath] = '/usr/share/one/Gemfile'
  opts.on('-g', '--gemfilepath PATH',
          'Path to gemfile (default: /usr/share/one/Gemfile)') do |path|
    options[:gemfilePath] = path
  end
  options[:installLocation] = '/usr/lib/one/gems'
  opts.on('-i', '--installlocation PATH',
          'Path where packages will be installed (default: /usr/lib/one/gems)') do |path|
    options[:installLocation] = path
  end
  options[:binPath] = nil
  opts.on('--gembinpath PATH',
          'Path where bin files of gems will be installed (default: installlocation/bin)') do |path|
    options[:binPath] = path
  end
  options[:packageLocation] = '.'
  opts.on('-p', '--packagelocation PATH',
          'Path where packages will be created (default: .)') do |path|
    options[:packageLocation] = path
  end
  options[:buildDirectory] = "#{__dir__}/build"
  opts.on('-b', '--builddirectory DIR',
          'Directory used for building gems (default: ./build)') do |path|
    options[:buildDirectory] = path
  end
  options[:namePrefix] = 'opennebula-rubygem'
  opts.on('-f', '--packagenameprefix NAME',
          'Prefix of created packages (default: opennebula-rubygem)') do |name|
    options[:namePrefix] = name
  end
  options[:packager] = 'OpenNebula'
  opts.on('--packager NAME',
          'Name of packager or maintainer (default: OpenNebula)') do |name|
    options[:packager] = name
  end
  options[:release] = 1
  opts.on('--release NUM', Integer,
          'Number of release or iteration (default: 1)') do |num|
    options[:release] = num
  end
  options[:chooseGems] = nil
  opts.on('--choose=GEMS',
          'Choose gems (separated by comma)') do |gems|
    options[:chooseGems] = gems
  end
  options[:excludeGems] = nil
  opts.on('--exclude=GEMS',
          'Exclude gems (separated by comma)') do |gems|
    options[:excludeGems] = gems
  end
  options[:show] = false
  opts.on('-s', '--show',
          'Show gems') do
    options[:show] = true
  end
  opts.on('-h', '--help',
          'Show this message') do
    puts opts
    exit
  end
end
optparser.parse!

if options[:chooseGems] &&
   options[:excludeGems]
  STDERR.puts "You can't both choose and exclude gems"
  exit 1
end

if options[:packageType] != 'deb' &&
   options[:packageType] != 'rpm' &&
   !options[:show]
  STDERR.puts 'unknown package type (-t TYPE)'
  exit 1
end

sorted_gems = sort_gems(
  get_gems_from_lockfile(
    parse_lockfile(
      options[:lockfilePath],
      options[:gemfilePath]
    )
  )
)

gems_to_pack = if options[:chooseGems]
                 choose_gems(sorted_gems, options[:chooseGems].split(','))
               elsif options[:excludeGems]
                 exclude_gems(sorted_gems, options[:excludeGems].split(','))
               else
                 sorted_gems
               end

if options[:show]
  gems_to_pack.each do |gem, version|
    puts gem + ' ' + version
  end
  exit 0
end

FileUtils.mkdir(options[:packageLocation]) unless
    Dir.exist?(options[:packageLocation])

build_dir = File.expand_path(options[:buildDirectory])
fpm_path = setup_fpm(build_dir)

options[:binPath] = "#{options[:installLocation]}/bin" if options[:binPath].nil?

gems_to_pack.each do |name, version|
  gem = { name: name,
          version: version,
          type: options[:packageType],
          package_location: options[:packageLocation],
          install_location: options[:installLocation],
          bin_path: options[:binPath],
          name_prefix: options[:namePrefix],
          packager: options[:packager],
          release_num: options[:release] }
  pack_gem(gem, build_dir, fpm_path)
end
exit 0
