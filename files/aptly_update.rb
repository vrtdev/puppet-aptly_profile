require_relative 'aptly'
require 'logger'

def default_value(value, default)
  return value unless value.nil?
  default
end

# Application logic to convert YAML in to aptly commands
class AptlyUpdate
  attr_accessor :logger
  attr_reader :aptly

  def initialize(
    separator = ' ',
    aptly = Aptly.new("#{separator}#{separator}")
  )
    @separator = separator
    @aptly = aptly
    @logger = Logger.new(nil)
  end

  def resolve_snapshot_initial(prefix, conf)
    # rubocop:enable Metrics/LineLength
    if conf.key?('snapshot')
      @logger.info "'#{prefix}': explicitly set to '#{conf['snapshot']}'"
      conf['snapshot']

    elsif conf.key?('script')
      @logger.info "'#{prefix}': running script"
      @aptly.update_mirror(conf['update']) if conf.key?('update')
      @aptly.script(conf['script'])

    elsif conf.key?('mirror')
      @logger.info "'#{prefix}': creating snapshot of mirror '#{conf['mirror']}'"
      @aptly.create_snapshot_mirror(conf['mirror'], prefix)

    elsif conf.key?('merge')
      @logger.info "'#{prefix}': creating merge snapshot"
      sources = conf['merge'].map.with_index(0) do |s, i|
        resolve_snapshot("#{prefix}#{@separator}#{i}", s)
      end
      @aptly.merge(prefix, sources)

    elsif conf.key?('repo')
      @logger.info "'#{prefix}': creating snapshot of local repo '#{conf['repo']}'"
      @aptly.create_snapshot_repo(conf['repo'], prefix)

    else
      STDERR.puts "#{prefix}: no recognized config, ignoring"
      nil
    end
  end

  def resolve_snapshot_lag_version(prefix, existing_snapshots, lag)
    if existing_snapshots[-lag - 1].nil?
      n = existing_snapshots.length
      snapshot = existing_snapshots[0]
      @logger.warn "#{prefix}: lag #{lag} versions => NOT ENOUGH HISTORY, using #{snapshot} (#{n} versions)"
    else
      snapshot = existing_snapshots[-lag - 1]
      @logger.info "#{prefix}: lag #{lag} versions => #{snapshot}"
    end
    snapshot
  end

  def resolve_snapshot_lag_time(prefix, existing_snapshots, lag)
    pivot = Time.new - lag
    pivot = pivot.strftime(@aptly.timefmt)

    # remove all candidates more recent than pivot
    candidates = existing_snapshots.select do |s|
      s =~ %r{#{@separator}#{@separator}(.*)$}
      Regexp.last_match(1) <= pivot
    end

    if candidates.empty?
      snapshot = existing_snapshots[0]
      @logger.warn "#{prefix}: lag #{lag} seconds (<= #{pivot}) => NOT ENOUGH HISTORY, using #{snapshot}"
    else
      snapshot = candidates[-1]
      @logger.info "#{prefix}: lag #{lag} seconds (<= #{pivot}): using #{snapshot}"
    end

    snapshot
  end

  def resolve_snapshot_lag(prefix, existing_snapshots, lag)
    return existing_snapshots[-1] if lag == '0' || lag == '0v' || lag == '0s'

    case lag
    when Numeric
      return resolve_snapshot_lag_version(prefix, existing_snapshots, lag)

    when %r{^(\d+)v$}
      return resolve_snapshot_lag_version(prefix, existing_snapshots, Regexp.last_match(1).to_i)

    when %r{^(\d+)s$}
      return resolve_snapshot_lag_time(prefix, existing_snapshots, Regexp.last_match(1).to_i)

    else
      @logger.warn "#{prefix}: lag: unknown lag: #{lag}"
      return existing_snapshots[-1]
    end
  end

  # filter `existing_snapshots` to only contain snapshots older than `snapshot`
  def filter_snapshots_old(existing_snapshots, snapshot)
    existing_snapshots.select do |s|
      s < snapshot
    end
  end

  def prune_old_snapshots(prefix, old_snapshots, keep)
    @logger.info "Cleaning up '#{prefix}': keeping #{keep} old snapshots. Currently #{old_snapshots.length} old snapshots"
    while old_snapshots.length > keep
      @logger.info "Removing snapshot '#{old_snapshots[0]}'"
      @aptly.drop_snapshot old_snapshots.shift
    end
  end

  def resolve_snapshot(prefix, conf)
    type = default_value(conf['type'], 'change')
    keep = default_value(conf['keep'], -1)
    lag  = default_value(conf['lag'], '0')

    @logger.info "Resolving what should go in '#{prefix}'"

    existing_snapshots = @aptly.snapshots.select { |s| s =~ %r{^#{prefix}#{@separator}#{@separator}} }.sort
    if type == 'once' && existing_snapshots.length
      snapshot = existing_snapshots[-1]
      @logger.info "#{prefix} resolved to #{snapshot}"
      return snapshot
    end

    snapshot = resolve_snapshot_initial(prefix, conf)
    return nil if snapshot.nil?

    snapshot = @aptly.snapshot_dedup(snapshot, existing_snapshots[-1]) if type == 'change'

    # Append current snapshot (if we actually created a new one)
    existing_snapshots.push snapshot if existing_snapshots[-1] != snapshot

    snapshot = resolve_snapshot_lag(prefix, existing_snapshots, lag)

    if keep >= 0
      prune_old_snapshots(prefix,
                          filter_snapshots_old(existing_snapshots, snapshot),
                          keep)
    end

    @logger.info "'#{prefix}' resolved to '#{snapshot}'"
    snapshot
  end

  # Main method: publish the given configuration at the given location
  def publish(publishing_point, config)
    @logger.info "Publishing point #{publishing_point}: starting"

    unless config.key?('components')
      @logger.warn "Publishing point `#{publishing_point}` has no components, skipping"
      return
    end

    architectures = config['architectures'] || ['all']

    to_pub = Hash[
      config['components'].map do |component, cconfig|
        [component, resolve_snapshot("#{publishing_point}#{@separator}#{component}", cconfig)]
      end
    ]

    # Resolve the name after the components
    # That way, the name-script is run with mirrors already updated
    name = publishing_point
    name = @aptly.script(config['name']) if config.key?('name')

    @logger.info "Publishing point #{publishing_point}: publishing as '#{name}'"
    @aptly.publish(name, to_pub, architectures)
  end

  def mirror(mirror, config)
    @aptly.create_mirror(mirror, config)
  end
end
