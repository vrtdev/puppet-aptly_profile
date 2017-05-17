#!/usr/bin/env ruby
# rubocop:disable Style/EmptyLines

require_relative 'aptly'
require_relative 'indent_logger'
require_relative 'aptly_update'

@logger = IndentLogger.new(Logger.new(STDOUT))
@logger.level = Logger::INFO
@logger.debug { raise 'Debug output should not be displayed' }

class AptlyMock1 < Aptly
  def snapshots
    []
  end

  def create_snapshot_mirror(mirror, prefix)
    raise 'Creating snapshot of wrong mirror' if mirror != 'm'
    @created_snapshot = "#{prefix}#{@separator}now"
  end

  def publish(path, components)
    @logger.debug { raise 'Debug output should not be displayed' }
    raise "Wrong path #{path}" if path != 'normal-mirror'
    raise "Wrong components: #{components.keys} vs ['main']" if components.keys != ['main']
    raise "Wrong snapshot: #{components['main']} != #{@created_snapshot}" if components['main'] != @created_snapshot
  end
end
@aptly_update = AptlyUpdate.new(' ', AptlyMock1.new('  '))
@aptly_update.logger = @logger
@aptly_update.aptly.logger = @logger
@aptly_update.publish('normal-mirror',
                      'components' => {
                        'main' => {
                          'mirror' => 'm'
                        }
                      })


class AptlyMock2 < Aptly
  def snapshots
    ['normal-mirror main  1veryold',
     'normal-mirror main  2old']
  end

  def create_snapshot_mirror(_mirror, prefix)
    @created_snapshot = "#{prefix}#{@separator}new"
  end

  def snapshot_diff(new, old)
    raise "wrong new snapshot #{new}" unless new == 'normal-mirror main  new'
    raise "wrong old snapshot #{old}" unless old == 'normal-mirror main  2old'
    true # different
  end

  def publish(path, _components)
    raise "wrong name: #{path}" unless path == 'script-name'
  end
end
@aptly_update = AptlyUpdate.new(' ', AptlyMock2.new('  '))
@aptly_update.logger = @logger
@aptly_update.aptly.logger = @logger
@aptly_update.publish('normal-mirror',
                      'components' => {
                        'main' => {
                          'mirror' => 'm'
                        }
                      },
                      'name' => 'echo "script-name"')

class AptlyMock3 < Aptly
  def snapshots
    ['mirror-dedup main  1veryold',
     'mirror-dedup main  2old']
  end

  def create_snapshot_mirror(_mirror, prefix)
    @created_snapshot = "#{prefix}#{@separator}new"
  end

  def snapshot_diff(new, old)
    raise "wrong new snapshot: #{new}" unless new == 'mirror-dedup main  new'
    raise "wrong old snapshot: #{old}" unless old == 'mirror-dedup main  2old'
    false # equal
  end

  def drop_snapshot(s)
    raise "dropping wrong snapshot #{s}" unless s == 'mirror-dedup main  new'
    @dropped = 1
  end

  def publish(_path, components)
    raise 'did not drop new snapshot' unless @dropped
    raise 'publishing wrong snapshot' unless components['main'] == 'mirror-dedup main  2old'
  end
end
@aptly_update = AptlyUpdate.new(' ', AptlyMock3.new('  '))
@aptly_update.logger = @logger
@aptly_update.aptly.logger = @logger
@aptly_update.publish('mirror-dedup',
                      'components' => {
                        'main' => {
                          'mirror' => 'm'
                        }
                      })


class AptlyMock4 < Aptly
  def initialize(*rest)
    super(*rest)
    @dropped = 0
  end

  def snapshots
    ['mirror-keep main  __1',
     'mirror-keep main  __2',
     'mirror-keep main  __3',
     'mirror-keep main  __4',
     'mirror-keep main  __5']
  end

  def create_snapshot_mirror(_mirror, prefix)
    @created_snapshot = "#{prefix}#{@separator}__6"
  end

  def snapshot_diff(_new, _old)
    true # different
  end

  def drop_snapshot(s)
    raise "dropping wrong snapshot #{s}" unless s =~ %r{^mirror-keep main  __}
    @dropped += 1
  end

  def publish(_path, _components)
    raise "did not drop correct number of old snapshots: #{@dropped}" unless @dropped == 4
  end
end
@aptly_update = AptlyUpdate.new(' ', AptlyMock4.new('  '))
@aptly_update.logger = @logger
@aptly_update.aptly.logger = @logger
@aptly_update.publish('mirror-keep',
                      'components' => {
                        'main' => {
                          'mirror' => 'm',
                          'keep' => 1
                        }
                      })


class AptlyMock5 < Aptly
  def snapshots
    []
  end

  def publish(path, components)
    raise 'Wrong path' if path != 'snapshot'
    raise "Wrong components: #{components.keys} vs ['main']" if components.keys != ['main']
    raise "Wrong snapshot: #{components['main']} != bla" if components['main'] != 'bla'
  end
end
@aptly_update = AptlyUpdate.new(' ', AptlyMock5.new('  '))
@aptly_update.logger = @logger
@aptly_update.aptly.logger = @logger
@aptly_update.publish('snapshot',
                      'components' => {
                        'main' => {
                          'snapshot' => 'bla'
                        }
                      })


class AptlyMock6 < Aptly
  def snapshots
    []
  end

  def publish(path, components)
    raise 'Wrong path' if path != 'script'
    raise "Wrong components: #{components.keys} vs ['main']" if components.keys != ['main']
    raise "Wrong snapshot: #{components['main']} != aptly" if components['main'] != 'aptly'
  end
end
@aptly_update = AptlyUpdate.new(' ', AptlyMock6.new('  '))
@aptly_update.logger = @logger
@aptly_update.aptly.logger = @logger
@aptly_update.publish('script',
                      'components' => {
                        'main' => {
                          'script' => 'echo "##APTLY##"'
                        }
                      })


class AptlyMock7 < Aptly
  def snapshots
    %w[one two]
  end

  def merge(prefix, sources)
    raise "Wrong prefix: #{prefix}" unless prefix == 'merge main'
    raise "wrong sources: #{sources}" unless sources == %w[one two]
    "#{prefix}#{@separator}now"
  end

  def publish(path, components)
    raise 'Wrong path' if path != 'merge'
    raise "Wrong components: #{components.keys} vs ['main']" if components.keys != ['main']
    raise "Wrong snapshot: #{components['main']} != \"merge main  now\"" if components['main'] != 'merge main  now'
  end
end
@aptly_update = AptlyUpdate.new(' ', AptlyMock7.new('  '))
@aptly_update.logger = @logger
@aptly_update.aptly.logger = @logger
@aptly_update.publish('merge',
                      'components' => {
                        'main' => {
                          'merge' => [
                            { 'snapshot' => 'one' },
                            { 'snapshot' => 'two' }
                          ]
                        }
                      })


class AptlyMock8 < Aptly
  def snapshots
    []
  end

  def create_snapshot_repo(repo, prefix)
    raise unless repo == 'local'
    "#{prefix}#{@separator}now"
  end

  def publish(path, components)
    raise 'Wrong path' if path != 'repo'
    raise "Wrong components: #{components.keys} vs ['main']" if components.keys != ['main']
    raise "Wrong snapshot: #{components['main']} != \"repo main  now\"" if components['main'] != 'repo main  now'
  end
end
@aptly_update = AptlyUpdate.new(' ', AptlyMock8.new('  '))
@aptly_update.logger = @logger
@aptly_update.aptly.logger = @logger
@aptly_update.publish('repo',
                      'components' => {
                        'main' => {
                          'repo' => 'local'
                        }
                      })


class AptlyMock9 < Aptly
  def initialize(*rest)
    super(*rest)
    # rubocop:disable Style/ExtraSpacing, Style/SpaceAroundOperators
    @snapshots = [
      "lag main  #{(Time.new - 3*86_400).strftime(@timefmt)}",
      "lag main  #{(Time.new - 2*86_400).strftime(@timefmt)}",
      "lag main  #{(Time.new -   86_400).strftime(@timefmt)}",
      "lag main  #{(Time.new -   86_000).strftime(@timefmt)}",
      "lag main  #{(Time.new -      300).strftime(@timefmt)}"
    ]
    # rubocop:enable Style/ExtraSpacing, Style/SpaceAroundOperators
  end
  attr_reader :snapshots

  def update_mirror(_m); end

  def snapshot_diff(_a, _b)
    true
  end

  def create_snapshot_mirror(_mirror, prefix)
    "#{prefix}#{@separator}#{Time.new.strftime(@timefmt)}"
  end

  def publish(_path, components)
    raise "wrong lag: #{components['main']}" unless components['main'] == @snapshots[2]
  end

  def drop_snapshot(snapshot)
    raise 'dropping wrong snapshot' unless snapshot == @snapshots[0]
  end
end
@aptly_update = AptlyUpdate.new(' ', AptlyMock9.new('  '))
@aptly_update.logger = @logger
@aptly_update.aptly.logger = @logger
@aptly_update.publish('lag',
                      'components' => {
                        'main' => {
                          'mirror' => 'm',
                          'lag' => '86400s',
                          'keep' => 1
                        }
                      })


class AptlyMock10 < Aptly
  def initialize(*rest)
    super(*rest)
    # rubocop:disable Style/ExtraSpacing, Style/SpaceAroundOperators
    @snapshots = [
      "lag main  #{(Time.new - 3*86_400).strftime(@timefmt)}",
      "lag main  #{(Time.new - 2*86_400).strftime(@timefmt)}",
      "lag main  #{(Time.new -   86_400).strftime(@timefmt)}",
      "lag main  #{(Time.new -   86_000).strftime(@timefmt)}",
      "lag main  #{(Time.new -      300).strftime(@timefmt)}"
    ]
    # rubocop:enable Style/ExtraSpacing, Style/SpaceAroundOperators
  end
  attr_reader :snapshots

  def update_mirror(_m); end

  def snapshot_diff(_a, _b)
    true
  end

  def create_snapshot_mirror(_mirror, prefix)
    "#{prefix}#{@separator}#{Time.new.strftime(@timefmt)}"
  end

  def publish(_path, components)
    raise "wrong lag: #{components['main']}" unless components['main'] == @snapshots[2]
  end

  def drop_snapshot(snapshot)
    raise "dropping wrong snapshot: #{snapshot}" unless snapshot == @snapshots[0]
  end
end
@aptly_update = AptlyUpdate.new(' ', AptlyMock10.new('  '))
@aptly_update.logger = @logger
@aptly_update.aptly.logger = @logger
@aptly_update.publish('lag',
                      'components' => {
                        'main' => {
                          'mirror' => 'm',
                          'lag' => '3v',
                          'keep' => 1
                        }
                      })
