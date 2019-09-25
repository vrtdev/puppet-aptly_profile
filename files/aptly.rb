require 'open3'
require 'logger'

# Wrapper class around aptly binary
class Aptly

  APTLY_VERSION_INTRODUCE_FORCE_COMPONENTS = Gem::Version.new('0.9')

  attr_reader :separator, :timefmt
  attr_accessor :logger

  def initialize(
    separator,
    aptly_cmd = 'aptly',
    timefmt = '%Y-%m-%dT%H-%M-%S'
  )
    @aptly_cmd = aptly_cmd
    @separator = separator
    @timefmt = timefmt
    @now = Time.new.strftime(timefmt)
    @updated_mirrors = {}
    @logger = Logger.new(nil)
  end

  # Custom exception to catch the command, exit code and output
  class RunError < RuntimeError
    attr_reader :command
    attr_reader :exitstatus
    attr_reader :output
    def initialize(cmd, es, out)
      @command = cmd
      @exitstatus = es
      @output = out
    end

    def message
      'Command `' + @command.map { |a| "'#{a}'" }.join(' ') + '` failed with ' \
        "exit code #{@exitstatus}"
    end
  end

  # Execute a command, wait for it to finish successfully and return the stdout.
  # In case of a command failure (non-0 exit code), throw a RunError with all
  # details
  #
  def run(*cmd)
    @logger.debug "Running command `#{cmd.map { |e| "'#{e}'" }.join(' ')}`"
    Open3.popen2e(*cmd) do |i, o, t|
      @logger.debug "PID=#{t.pid}"
      i.close
      output = o.read
      o.close
      t.join
      @logger.debug "RV=#{t.value.exitstatus}"
      if t.value.exitstatus.nonzero?
        raise RunError.new(cmd, t.value.exitstatus, output)
      end

      @logger.debug output
      output
    end
  end
  # rubocop:enable Metrics/AbcSize
  # rubocop:enable Metrics/MethodLength

  # Run a script, wait for it to finish successfully and return stdout.
  # In case of a failure (non-0 exit code), throw a RunError with all the
  # details
  # the string "##APTLY##" (without quotes) will be replaced with the aptly
  # command that is configured for the Aptly-object
  #
  # rubocop:disable Metrics/BlockLength
  def script(cmd)
    cmd.gsub!(%r{##APTLY##}, @aptly_cmd)
    @logger.debug "Running command `#{cmd}`"
    Open3.popen3(cmd) do |i, o, e, t|
      @logger.debug "PID=#{t.pid}"
      i.close
      outs = [o, e]
      output = ''
      mixed = ''
      until outs.find { |f| !f.eof }.nil?
        ready_read, _ready_write, _ready_error = IO.select(outs)
        begin
          if ready_read.find { |f| f == o }
            temp = o.read_nonblock(4096)
            output += temp
            mixed += temp
          end
          mixed += e.read_nonblock(4096) if ready_read.find { |f| f == e }
        rescue EOFError => e # rubocop:disable Lint/HandleExceptions
          # ignore, handled in until-loop conditional
        end
      end

      t.join
      @logger.debug "RV=#{t.value.exitstatus}"
      if t.value.exitstatus.nonzero?
        raise RunError.new(cmd, t.value.exitstatus, mixed)
      end

      output.chomp!
      @logger.debug mixed
      @logger.debug "Returned: #{output}"
      output
    end
  end
  # rubocop:enable Metrics/AbcSize
  # rubocop:enable Metrics/MethodLength

  def mirrors
    run(@aptly_cmd, 'mirror', 'list', '-raw').lines.map(&:chomp)
  end

  def snapshots
    run(@aptly_cmd, 'snapshot', 'list', '-raw').lines.map(&:chomp)
  end

  def publish_points
    run(@aptly_cmd, 'publish', 'list', '-raw').lines.map(&:chomp)
  end

  def aptly_version
    run(@aptly_cmd, 'version').split.last.scan(/\d+/).join('.')
  end

  # Update the specified mirror(s)
  # A mirror will only be updated once. Subsequent update_mirror() calls for
  # the same mirror will return immediately
  def update_mirror(*mirrors)
    mirrors.each do |mirror|
      if @updated_mirrors.key?(mirror)
        @logger.info "Updating mirror #{mirror} already done, skipping"
      else
        @logger.info "Updating mirror #{mirror}"
        run(@aptly_cmd, 'mirror', 'update', mirror)
        @updated_mirrors[mirror] = 'done'
      end
    end
  end

  # Create a snapshot from the given mirror. The snapshot will be named
  # according to the current time, with the given prefix.
  # Returns the name of the newly created snapshot
  def create_snapshot_mirror(mirror, prefix)
    snapshot = "#{prefix}#{@separator}#{@now}"
    @logger.info "Creating snapshot from mirror \"#{mirror}\" at \"#{snapshot}\""

    update_mirror(mirror)
    run(@aptly_cmd, 'snapshot', 'create', snapshot,
        'from', 'mirror', mirror)

    snapshot
  end

  def create_snapshot_repo(repo, prefix)
    snapshot = "#{prefix}#{@separator}#{@now}"
    @logger.info "Creating snapshot from repo \"#{repo}\" at \"#{snapshot}\""

    run(@aptly_cmd, 'snapshot', 'create', snapshot,
        'from', 'repo', repo)

    snapshot
  end

  def drop_snapshot(name)
    @logger.info "Dropping snapshot \"#{name}\""

    descr = run(@aptly_cmd, 'snapshot', 'show', name).
            lines.map(&:chomp).
            find { |l| l =~ %r{^Description: } }
    descr.sub!(%r{^Description: }, '')

    begin
      run(@aptly_cmd, 'snapshot', 'drop', name)
    rescue RunError => e
      if e.output =~ %r{^ERROR: unable to drop: snapshot is published}
        @logger.warn "Snapshot '#{name}' is published somewhere else, retaining"
      elsif e.output =~ %r{^ERROR: won't delete snapshot that was used as source for other snapshots}
        @logger.warn "Snapshot '#{name}' is merged somewhere else, retaining"
      else
        raise
      end
    end

    return unless descr =~ %r{^Merged from sources: }
    descr.sub!(%r{^Merged from sources: }, '')
    @logger.debug "'#{name}' is a merge commit, descending"
    descr.split(%r{, }).each do |s|
      drop_snapshot(s.sub(%r{^'(.*)'$}, '\1'))
    end
  end
  # rubocop:enable Metrics/AbcSize
  # rubocop:enable Metrics/MethodLength

  # Compare 2 snapshots
  # Return true if they differ
  def snapshot_diff(a, b)
    out = run(@aptly_cmd, 'snapshot', 'diff', a, b)
    out !~ %r{Snapshots are identical}
  end

  def snapshot_dedup(new_one, old_one)
    return new_one if old_one.nil?
    return new_one if snapshot_diff(new_one, old_one)

    @logger.info "Snapshot '#{new_one}' is duplicate, replacing by '#{old_one}'"
    drop_snapshot(new_one)
    old_one
  end

  def merge(prefix, sources)
    snapshot = "#{prefix}#{@separator}#{@now}"
    @logger.info "Creating merge snapshot '#{snapshot}'"

    run(@aptly_cmd, 'snapshot', 'merge', snapshot, *sources)

    snapshot
  end

  def create_mirror(name, config)
    if mirrors.include?(name)
      @logger.info("Mirror #{name} already exists, skipping")
      return
    end

    raise RunError.new([], 255, "Mirror #{name} has no location") unless config['location']
    raise RunError.new([], 255, "Mirror #{name} has no release") unless config['release']

    config = {
      'with_sources'     => false,
      'with_udebs'       => false,
      'filter_with_deps' => false,
      'architectures'    => [],
      'environment'      => [],
      'filter'           => '',
      'force_components' => false

    }.merge(config)
    args = %w[mirror create]

    unless config['architectures'].empty?
      args << '-architectures=' + [config['architectures'].flatten].join(',')
    end
    args << '-with-sources=' + config['with_sources'].to_s
    args << '-with-udebs=' + config['with_udebs'].to_s
    args << '-filter="' + config['filter'] + '"' unless config['filter'].empty?

    if Gem::Version.new(aptly_version) >= APTLY_VERSION_INTRODUCE_FORCE_COMPONENTS
      args << '-force-components=' + config['force_components'].to_s
    end

    args << '-filter-with-deps' if config['filter_with_deps']

    args << name
    args << config['location']
    args << config['release']
    args << config['repos'].join(' ') unless config['repos'].empty?
    @logger.info("Creating mirror #{name} => #{config['location']}")
    run(@aptly_cmd, *args)
  end

  def publish(path, components, architectures)
    # Publish-or-switch wrapper
    prefix, distribution = path.match(%r{(?:(.*)/)?([^/]+)}).captures
    prefix = '.' if prefix.nil?

    if publish_points.include?("#{prefix} #{distribution}")
      @logger.info "publish point '#{path}' => ('#{prefix}', '#{distribution}') to be switched"
      run(@aptly_cmd, 'publish', 'switch',
          '-component=' + components.keys.join(','),
          '-force-overwrite=true',
          distribution, prefix,
          *components.values)
    else
      @logger.info "publish point '#{path}' => ('#{prefix}', '#{distribution}') to be created"
      run(@aptly_cmd, 'publish', 'snapshot',
          '-distribution=' + distribution,
          '-architectures=' + architectures.join(','),
          '-component=' + components.keys.join(','),
          *components.values,
          prefix)
    end
  end
  # rubocop:enable Metrics/AbcSize
  # rubocop:enable Metrics/MethodLength

  def cleanup
    @logger.info 'Cleaning up DB'
    run(@aptly_cmd, 'db', 'cleanup')
  end
end
