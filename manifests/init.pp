#
# Installs an aptly server on the host, mirrors the repos listed in hiera, and
# serves the (manually) published repos via apache
#
# @param aptly_user User aptly is running as.
# @param aptly_group Group aptly is running as.
# @param aptly_homedir Homedir for aptly.
# @param trusted_keys Hash with trusted keys.
# @param publish Hash with the publish configuration.
# @param mirrors Hash with the mirrors to configure.
# @param aptly_environment An array with custom environment settings for the cron job.
#
class aptly_profile(
  String $aptly_user = 'aptly',
  String $aptly_group = 'users',
  String $aptly_homedir = '/data/aptly',
  Hash $trusted_keys = {},
  Hash $publish = {},
  Hash $mirrors = {},
  Array[String] $aptly_environment = [],
){

  # User, group and homedir
  #########################
  user {$aptly_user:
    ensure => present,
    gid    => $aptly_group,
    home   => $aptly_homedir,
  }

  group {$aptly_group:
    ensure => present,
  }

  file { $aptly_homedir:
    ensure  => 'directory',
    owner   => $aptly_user,
    group   => $aptly_group,
    require => User[$aptly_user],
  }

  file { "${aptly_homedir}/public":
    ensure  => 'directory',
    owner   => $aptly_user,
    group   => $aptly_group,
    require => User[$aptly_user],
  }

  # Aptly itself
  ##############
  class { '::aptly':
    user          => $aptly_user,
    repo          => false, # don't include aptly.info repo
    config        => {
      rootDir => $aptly_homedir,
    },
    aptly_mirrors => {},
    require       => File[$aptly_homedir],
  }
  # ::aptly will read the mirrors to make from hiera
  # You will still need to manually update them (or wait for the cron below to
  # run

  create_resources('::aptly_profile::trusted_key', $trusted_keys)

  # Pass through the aptly_environment to the execs used for mirroring
  create_resources('::aptly::mirror', $mirrors, { 'environment' => $aptly_environment })

  file { '/usr/bin/aptly-lock':
    owner  => 'root',
    group  => 'root',
    mode   => '0755',
    source => 'puppet:///modules/aptly_profile/aptly-lock',
  }

  # Automatic management (cron)
  #############################
  file { "${aptly_homedir}/aptly-update.rb":
    owner   => $aptly_user,
    group   => $aptly_group,
    mode    => '0755',
    source  => 'puppet:///modules/aptly_profile/aptly-update.rb',
    require => File[
      "${aptly_homedir}/aptly_update.rb",
      "${aptly_homedir}/aptly.rb",
      "${aptly_homedir}/indent_logger.rb",
      '/usr/bin/aptly-lock',
    ],
  }
  file { "${aptly_homedir}/aptly_update.rb":
    owner  => $aptly_user,
    group  => $aptly_group,
    mode   => '0644',
    source => 'puppet:///modules/aptly_profile/aptly_update.rb',
  }
  file { "${aptly_homedir}/aptly.rb":
    owner  => $aptly_user,
    group  => $aptly_group,
    mode   => '0644',
    source => 'puppet:///modules/aptly_profile/aptly.rb',
  }
  file { "${aptly_homedir}/indent_logger.rb":
    owner  => $aptly_user,
    group  => $aptly_group,
    mode   => '0644',
    source => 'puppet:///modules/aptly_profile/indent_logger.rb',
  }

  cron { 'aptly-update':
    command     => "${aptly_homedir}/aptly-update.rb >/dev/null",
    user        => $aptly_user,
    require     => [
      User[$aptly_user],
      File["${aptly_homedir}/aptly-update.rb"],
    ],
    hour        => 3,
    minute      => 17,
    environment => $aptly_environment,
  }

  file { "${aptly_homedir}/publish.yaml":
    owner   => $aptly_user,
    group   => $aptly_group,
    mode    => '0644',
    content => inline_template("<%= @publish.to_hash.to_yaml %>\n"),
  }


  # Publishing
  ############
  class { '::apache':
    default_vhost => false,
    default_mods  => false,
  }

  class { '::apache::mod::dir': }
  class { '::apache::mod::autoindex': }

  ::apache::vhost { 'aptly':
    port           => 80,
    docroot        => "${aptly_homedir}/public",
    require        => File["${aptly_homedir}/public"],
    manage_docroot => false,
  }


  # Repo Singing Key management
  #############################

  # Mostly copy-paste from `gpg_key::keypair`
  # We can't use the `gpg_key::keypair` defined type, because we need access
  # to the $key variable to create our `apt::key` resource

  include ::gpg_key # To make the parent directory
  $basename = '/etc/gpg_keys/aptly'

  $existing_key = gpg_find_key($::gpg_keys, {
      'secret_present' => true,
      'basename'       => 'aptly',
  })

  if $existing_key {
    $key = $existing_key
    file { "${basename}.sec":
      ensure  => file,
      owner   => $aptly_user,
      group   => 'root',
      mode    => '0400',
      content => undef,
    }
  } else { # no existing key
    $generated_key = gpg_generate_key({
        'uid' => 'VRT DPC repo singing key',
    })
    $key = $generated_key

    file { "${basename}.sec":
      ensure  => file,
      owner   => $aptly_user,
      group   => 'root',
      mode    => '0400',
      content => $generated_key['secret_key'],
    }
  }

  file { "${basename}.pub":
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0444',
    content => $key['public_key'],
  }

  @@::apt::key { "aptly key ${::hostname}":
    id      => $key['fingerprint'],
    content => $key['public_key'],
  }

  # Aptly expects the signing key to be in its GnuPG keyring
  # Import/replace it
  exec { 'aptly_profile::init import aptly GPG key in to keyring':
    creates     => "${aptly_homedir}/.gnupg/secring.gpg",
    user        => $aptly_user,
    environment => ["HOME=${aptly_homedir}"],
    cwd         => $aptly_homedir,
    command     => "/usr/bin/gpg --import '${basename}.sec'",
  }
  exec { 'aptly_profile::init update aptly GPG key in keyring':
    refreshonly => true,
    subscribe   => File["${basename}.sec"],
    user        => $aptly_user,
    environment => ["HOME=${aptly_homedir}"],
    cwd         => $aptly_homedir,
    command     => "/bin/rm -f .gnupg/secring.gpg; /usr/bin/gpg --import '${basename}.sec'",
  }

}
