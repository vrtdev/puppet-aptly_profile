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


$debug = false
$separator = " " # A character that is guaranteed not apear in mirror, snapshot & publish names

$aptly_cmd = '/usr/bin/aptly-lock'

require 'open3'
require 'yaml'


class RunError < RuntimeError
	attr :command
	attr :exitstatus
	attr :output
	def initialize(cmd, es, out)
		@command = cmd
		@exitstatus = es
		@output = out
	end
	def message
		"Command `" + @command.map {|a| "'#{a}'" }.join(' ') + "` failed with " +
			"exit code #{@exitstatus}"
	end
end

def vprint(*args)
	printf (" " * caller.size) + args.join('')
end
def dprint(*args)
	if $debug
		printf (" " * caller.size) + args.join('')
	end
end


def run(*cmd)
	dprint "Running command `#{ cmd.map{|e| "'#{e}'"}.join(' ') }`\n"
	Open3.popen2e(*cmd) { |i,o,t|
		dprint "PID=#{t.pid}\n"
		i.close
		output = o.read
		o.close
		t.join
		dprint "RV=#{t.value.exitstatus}\n"
		if t.value.exitstatus != 0
			raise RunError.new(cmd, t.value.exitstatus, output)
		end

		dprint output
		output
	}
end

def script(cmd)
	dprint "Running command `#{cmd}`\n"
	Open3.popen3(cmd) { |i,o,e,t|
		dprint "PID=#{t.pid}\n"
		i.close
		outs = [o,e]
		output = ""
		mixed = ""
		until outs.find { |f| !f.eof }.nil? do
			ready_read, ready_write, ready_error = IO.select(outs)
			begin
				if ready_read.find {|f| f == o }
					temp = o.read_nonblock(4096)
					output += temp
					mixed += temp
				end
				if ready_read.find {|f| f == e }
					mixed += e.read_nonblock(4096)
				end
			rescue EOFError => e
				# ignore
			end
		end

		t.join
		dprint "RV=#{t.value.exitstatus}\n"
		if t.value.exitstatus != 0
			raise RunError.new(cmd, t.value.exitstatus, mixed)
		end

		output.chomp!
		dprint mixed
		dprint "Returned: #{output}\n"
		output
	}
end

$updated_mirrors = {}
def update_mirror(mirror)
	if $updated_mirrors.has_key?(mirror)
		dprint "Updating mirror #{mirror}... already done\n"
	else
		vprint "Updating mirror #{mirror}\n"
		run($aptly_cmd, 'mirror', 'update', mirror)
		$updated_mirrors[mirror] = "done"
	end
end

def create_snapshot_mirror(mirror, prefix)
	update_mirror( mirror )
	snapshot = "#{prefix}#{$separator}#{$separator}#{$now}"
	run($aptly_cmd, 'snapshot', 'create', snapshot,
	    'from', 'mirror', mirror
	   )

	snapshot
end

def create_snapshot_repo(repo, prefix)
	snapshot = "#{prefix}#{$separator}#{$separator}#{$now}"
	run($aptly_cmd, 'snapshot', 'create', snapshot,
	    'from', 'repo', repo
	   )

	snapshot
end

def drop_snapshot(name)
	vprint "Droping snapshot '#{name}'\n"

	descr = run($aptly_cmd, 'snapshot', 'show', name).lines.map(&:chomp)
	         .select{ |l| l =~ /^Description: / }.first
	descr.sub!(/^Description: /, '')

	begin
		run($aptly_cmd, 'snapshot', 'drop', name)
	rescue RunError => e
		if e.output =~ /^ERROR: unable to drop: snapshot is published/
			vprint "Snapshot '#{name}' is published somewhere else, retaining\n"
		elsif e.output =~ /^ERROR: won't delete snapshot that was used as source for other snapshots/
			vprint "Snapshot '#{name}' is merged somewhere else, retaining\n"
		else
			raise
		end
	end

	if descr =~ /^Merged from sources: /
		descr.sub!(/^Merged from sources: /, '')
		dprint "'#{name}' is a merge commit, descending\n"
		descr.split(/, /).each { |s|
			drop_snapshot( s.sub(/^'(.*)'$/, '\1') )
		}
	end

end

def snapshot_dedup(new_one, prefix)
	previous_snapshot = $snapshots.select {|s| s =~ /^#{prefix}#{$separator}#{$separator}/ }.sort.last
	if previous_snapshot.nil?
		return new_one
	end
	out = run($aptly_cmd, 'snapshot', 'diff', new_one, previous_snapshot)
	if out =~ /Snapshots are identical/
		vprint "Snapshot '#{new_one}' is duplicate, replacing by '#{previous_snapshot}'\n"
		drop_snapshot(new_one)
		return previous_snapshot
	else
		return new_one
	end
end

def merge(prefix, sources)
	vprint "Creating merge snapshot '#{prefix}'\n"

	snapshot = "#{prefix}#{$separator}#{$separator}#{$now}"

	sources = sources.map.with_index(0){ |s,i|
		resolve_snapshot("#{prefix}#{$separator}#{i}", s)
	}

	run($aptly_cmd, 'snapshot', 'merge', snapshot, *sources)

	snapshot
end

def resolve_snapshot(prefix, conf)
	vprint "Resolving what should go in '#{prefix}'\n"
	snapshot = nil

	if conf.has_key?('snapshot')
		snapshot = conf['snapshot']

	elsif conf.has_key?('script')
		if conf.has_key?('update')
			to_update = conf['update']
			if to_update.class == String
				to_update = [ to_update ]
			end
			to_update.each { |m|
				update_mirror(m)
			}
		end
		snapshot = script(conf['script'])

	elsif conf.has_key?('mirror')
		snapshot = create_snapshot_mirror(conf['mirror'], prefix)

	elsif conf.has_key?('merge')
		snapshot = merge(prefix, conf['merge'])

	elsif conf.has_key?('repo')
		snapshot = create_snapshot_repo(prefix, conf['repo'])

	else
		STDERR.puts "#{prefix}: no recognized config, ignoring"
		return nil
	end

	type = 'change'
	if conf.has_key?('type')
		type = conf['type']
	end
	keep = -1
	if conf.has_key?('keep')
		keep = conf['keep']
	end

	case type
	when 'everytime'
		# done

	when 'once'
		prev = $snapshots.select{ |s| s =~ /^#{prefix}#{$separator}#{$separator}/ }.last
		if not prev.nil?
			vprint "'#{prefix}' type=once, using '#{prev}'\n"
			drop_snapshot(snapshot)
			snapshot = prev
		end

	else # and case 'change', which is default
		STDERR.puts "#{prefix}: unrecognized type #{type}, defaulting to 'change'" if type != 'change'
		dedup = snapshot_dedup(snapshot, prefix)
		if dedup != snapshot
			snapshot = dedup
			keep += 1 if keep >= 0 # keep one more, since we don't have a "new" copy
		end
	end


	if keep >= 0
		dprint "Cleaning up '#{prefix}': keeping #{keep} old snapshots\n"
		prev = $snapshots.select{ |s| s =~ /^#{prefix}#{$separator}#{$separator}/ }.sort
		while prev.length > keep.to_i
			vprint "snapshot '#{prev[0]}': to remove\n"
			$ss_to_drop.push(prev[0])
			prev.shift
		end
	end

	vprint "'#{prefix}' resolved to '#{snapshot}'\n"
	snapshot
end

def publish(path, components)
	# Publish-or-switch wrapper
	prefix, distribution = path.match(/(?:(.*)\/)?([^\/]+)/).captures
	if prefix == nil
		prefix = "."
	end

	if $publish.include?("#{prefix} #{distribution}")
		vprint "publish point '#{path}' => ('#{prefix}', '#{distribution}') to be switched\n"
		run($aptly_cmd, 'publish', 'switch',
		    '-component=' + components.keys.join(','),
		    distribution, prefix,
		    *components.values
		   )
	else
		vprint "publish point '#{path}' => ('#{prefix}', '#{distribution}') to be created\n"
		run($aptly_cmd, 'publish', 'snapshot',
		    '-distribution=' + distribution,
		    '-component=' + components.keys.join(','),
		    *components.values,
		    prefix
		   )
	end
end

begin
	config = YAML.load_file('publish.yaml')

	vprint "Getting current state\n"
	$now = Time.new.strftime("%Y-%m-%dT%H-%M-%S") # Make sure these sort correctly
	$mirrors = run($aptly_cmd, 'mirror', 'list', '-raw').lines.map(&:chomp)
	$snapshots = run($aptly_cmd, 'snapshot', 'list', '-raw').lines.map(&:chomp)
	$publish = run($aptly_cmd, 'publish', 'list', '-raw').lines.map(&:chomp)
	$ss_to_drop = []

	vprint "Generating publishing points\n"
	config.each_pair { |pub, c|
		vprint "#{pub}: finding out what should go in"

		if not c.has_key?('components')
			STDERR.puts "Publishing point `#{pub}` has no components, skipping"
			next
		end

		to_pub = Hash[ c['components'].map{ |comp,cont|
			[comp, resolve_snapshot("#{pub}#{$separator}#{comp}", cont)]
		}]

		name = pub
		if c.has_key?('name')
			name = script(c['name'])
		end
		vprint "#{pub}: name=#{name}\n"

		publish(name, to_pub)
	}

	vprint "Dropping old snapshots\n"
	$ss_to_drop.each { |s|
		vprint "Dropping '#{s}'\n"
		drop_snapshot(s)
	}

	vprint "Cleaning up DB\n"
	run($aptly_cmd, 'db', 'cleanup')

rescue RunError => e
	STDERR.puts "Running command failed"
	STDERR.puts "   " + e.command.map {|a| "'#{e}'" }.join(' ')
	STDERR.puts "Output:"
	STDERR.puts e.output
	STDERR.puts " Exit code: #{e.exitstatus}"
end
