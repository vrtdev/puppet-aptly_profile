#!/usr/bin/env ruby
## File managed by puppet
#  * Module: aptly_profile
#  * File:   aptly-update.rb

# Updates the published repositories per config file
#
# Config file syntax:
# ---
# debian/jessie:   # The publishing point to publish under
#                  # may include a prefix.
#   components:
#     main:          # component to publish under
#                    # To use this example, you need: deb http://bla/debian/ jessie main
#       mirror: jessie-main       # Creates a fresh snapshot of the `jessie-main`
#                                 # mirror on every run
#       keep: 1                   # Keep 1 old copy around. Default: -1 (keep forever)
#     puppet:
#       snapshot: whatever        # Use a named snapshot
#
# debian/jessie-with-updates:
#   components:
#     main:
#       merge:       # make a merge snapshot containing:
#         - mirror: jessie-main    # This will re-use the snapshot made earlier
#                                  # for the `debian/jessie` repo
#         - mirror: jessie-updates
#           type: everytime        # when to create a snapshot:
#                                  # `everytime` makes a snapshot every time
#                                  #             this script is run
#                                  # `once` make a snapshot when one doesn't
#                                  #        exist
#                                  # `change` (default) only creates a snapshot
#                                  #          if things have chaned
#       keep: 5                    # Keep this many old copies for the merged
#                                  # snapshot
#                                  # Child snapshots are removed as soon as they
#                                  # are no longer referenced
# debian/jessie-today:
#   name: echo "jessie-$(date)"    # Shell script that will output the name
#                                  # Useful for dynamic names.
#   components:
#     main:
#       script: |                 # Script that outputs the name of the
#         echo "jessie-$(date)"   # snapshot to publish. The script should
#                                 # make sure that the snapshot actually
#                                 # exists
#                                 # `keep` is not supported with `script`
#                                 # snapshots
#       update: mirror            # Update these mirror(s) before running the
#                                 # script
# dabian/jessie-yesterday:
#   companents:
#     main:
#       mirror: jessie-main
#       lag: 86400s               # Use the jessie-main mirror, but from (at
#                                 # least) 1 day ago
#                                 # You can also specify "5v", to lag 5 versions
#                                 # If not enough history is available, the
#                                 # oldest version will be used and a warning
#                                 # printed
# local:
#   components:
#     main:
#       repo: local            # Create a fresh snapshot of the local repo
#                              # `repo`
#       keep: 5
#
# General remark for scripts: Don't ever run two aptly's in parallel.
# Aptly locks its database, so even this sometimes fails:
#     aptly bla list -raw | while read a; do
#         aptly bla drop $a
#     done
#
# General remark on names: Don't use spaces, comma's, single or double quotes

require 'yaml'
require 'optparse'
require_relative 'indent_logger'
require_relative 'aptly'
require_relative 'aptly_update'

@options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: #{__FILE__} [options] <publishing point>"

  opts.on('-v', '--[no-]verbose', 'Run verbosely') do |v|
    @options[:verbose] = v
  end

  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.parse!


@logger = IndentLogger.new(Logger.new(STDOUT))
@logger.level = @options[:verbose] ? Logger::DEBUG : Logger::INFO

@aptly = Aptly.new('  ', '/usr/bin/aptly-lock')
@aptly.logger = @logger
@aptly_update = AptlyUpdate.new(' ', @aptly)
@aptly_update.logger = @logger

begin
  filename = 'publish.yaml'
  @logger.info "Generating publishing points for `#{filename}`"
  config = YAML.load_file(filename) || {}
  if config.empty?
    @logger.info "No publishing points found in `#{filename}`. Exiting."
  else
    config.each_pair do |pub, c|
      if ARGV.include?(pub)
        @aptly_update.publish(pub, c)
      end
    end
    @aptly.cleanup
  end

rescue Aptly::RunError => e
  STDERR.puts 'Running command failed'
  STDERR.puts '   ' + e.command.map { |_a| "'#{e}'" }.join(' ')
  STDERR.puts 'Output:'
  STDERR.puts e.output
  STDERR.puts " Exit code: #{e.exitstatus}"
end
