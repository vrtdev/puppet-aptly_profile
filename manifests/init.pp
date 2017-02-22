#
# Installs an aptly server on the host, mirrors the repos listed in hiera, and
# serves the (manually) published repos via apache
#
# @param aptly_user         User aptly is running as.
# @param aptly_group        Group aptly is running as.
# @param aptly_homedir      Homedir for aptly.
# @param aptly_shell        Shell for user aptly.
# @param cleanup_script     String with path to cleanup script
# @param cleanup_defaults   String with default options to pass on to a cleanup for a repo
# @param trusted_keys       Hash with trusted keys.
# @param publish            Hash with the publish configuration.
# @param mirrors            Hash with the mirrors to configure.
# @param repos              Hash with the repositories to create.
# @param mirror_defaults    Hash with default properties to set on mirrors.
#   Note, we map the environment property to `aptly_environment` by default even if it is
#   not defined in the mirror_defaults.
# @param repo_defaults      Hash with default properties to set on repos.
# @param aptly_environment  An array with custom environment settings for the cron job.
# @param publish_defaults   A hash with default properties to set on publishing points.
# @param insert_hello_script  Override the location where to put the insert_hello script.
# @param insert_hello Boolean indicating if you want te hello world package to be included
#   in newly created repositories.
# @param aptly_cache_dir   Directory where aptly can cache some data (the hello world package)
#
class aptly_profile(
  String $aptly_user = 'aptly',
  String $aptly_group = 'users',
  String $aptly_homedir = '/data/aptly',
  String $aptly_shell = '/bin/bash',
  String $cleanup_script = "${aptly_homedir}/cleanup_repo.sh",
  String $cleanup_defaults = '--keep 5 --days 3650 --package all --noop',
  Hash $trusted_keys = {},
  Hash $publish = {},
  Hash $mirrors = {},
  Hash $repos = {},
  Hash $mirror_defaults = {},
  Hash $repo_defaults = {},
  Hash $publish_defaults = {},
  Array[String] $aptly_environment = [],
  Stdlib::Absolutepath $insert_hello_script = "${aptly_homedir}/insert_hello.sh",
  Stdlib::ABsolutepath $aptly_cache_dir     = '/var/cache/aptly',
  Boolean $insert_hello                     = true,
){

  # User, group and homedir
  #########################
  user {$aptly_user:
    ensure => present,
    gid    => $aptly_group,
    home   => $aptly_homedir,
    shell  => $aptly_shell,
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

  $_mirror_defaults = merge({'environment' => $aptly_environment}, $mirror_defaults)


  # Pass through the aptly_environment to the execs used for mirroring
  create_resources('::aptly::mirror', $mirrors, $_mirror_defaults)

  $cleanup_cronjob = "${aptly_homedir}/cron_cleanup_repo.sh"

  concat { $cleanup_cronjob:
    ensure => present,
    mode   => '0755',
  }

  concat::fragment { 'cron_cleanup_repo_header':
    target  => $cleanup_cronjob,
    order   => 0,
    content => '#!/bin/bash
#
# This file is managed by puppet and build from concat fragments in aptly_profile
#
',
  }

  # Filter out our cleanup options, which are used only for the cronjob and not the repo resource
  $repos.each |String $repo_name, Hash $repo_config| {
    if has_key($repo_config, 'cleanup_options') {
      $filtered_repo_config = delete_regex($repo_config, 'cleanup_options')
      concat::fragment { "${repo_name}_cleanup":
        target  => $cleanup_cronjob,
        order   => 20,
        content => "${cleanup_script} --repo ${repo_name} ${repo_config['cleanup_options']}\n",
      }
    }
    else {
      $filtered_repo_config = $repo_config
      concat::fragment { "${repo_name}_cleanup":
        target  => $cleanup_cronjob,
        order   => 20,
        content => "${cleanup_script} --repo ${repo_name} ${cleanup_defaults}\n",
      }
    }

    $combined_repo_config = merge($filtered_repo_config, $repo_defaults)

    # Create aptly repo
    ::aptly::repo { $repo_name:
      * => $combined_repo_config,
    }
    if $insert_hello {
      exec {"aptly_profile::insert_hello: ${repo_name}":
        command     => shell_join([
          $insert_hello_script, '--repo', $repo_name,
        ]),
        user        => $aptly_user,
        refreshonly => true,
        subscribe   => Exec["aptly_repo_create-${repo_name}"],
        require     => File[$insert_hello_script],
      }
    }
  }

  # Cronjob to cleanup repo
  cron { 'auto cleanup repos':
    user    => $aptly_user,
    hour    => '22',
    minute  => '15',
    command => "${cleanup_cronjob} | logger",
  }

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

  $publish_d = "${aptly_homedir}/publish.d"

  file {$publish_d:
    ensure => 'directory',
    owner  => $aptly_user,
    group  => $aptly_group,
    mode   => '0755',
    purge  => true,
  }

  file {"${publish_d}/00_CONTENTS_WARNING":
    ensure => 'file',
    owner  => $aptly_user,
    group  => $aptly_group,
    mode   => '0644',
    source => 'puppet:///modules/aptly_profile/publish_d-header',
  }

  file {"${aptly_homedir}/publish.yaml":
    ensure => 'absent',
  }

  # cron with empty array keeps generating catalog changes
  $real_aptly_env = ifelse(empty($aptly_environment), undef, $aptly_environment)

  cron { 'aptly-update':
    command     => "${aptly_homedir}/aptly-update.rb >/dev/null",
    user        => $aptly_user,
    require     => [
      User[$aptly_user],
      File["${aptly_homedir}/aptly-update.rb", $publish_d],
    ],
    hour        => 3,
    minute      => 17,
    environment => $real_aptly_env,
  }

  $publish.each |String $publish_name, Hash $config| {
    # lint:ignore:variable_scope
    ## see https://github.com/rodjek/puppet-lint/issues/464

    if has_key($config, 'instant_publish') {
      $instant_publish = $config['instant_publish']
      # lint:endignore
    }
    else {
      $instant_publish = false
    }
    aptly_profile::publish {$publish_name:
      config          => $config,
      instant_publish => $instant_publish,
    }

    $ifrepo = find_key($config, 'repo')
    if ($ifrepo != undef) {
      Aptly_profile::Publish[$publish_name] {
        require => Aptly::Repo[$ifrepo],
      }
    }
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

  # Cleanup script
  ################
  file { $cleanup_script:
    ensure => file,
    owner  => $aptly_user,
    group  => $aptly_group,
    mode   => '0755',
    source => 'puppet:///modules/aptly_profile/cleanup_repo.sh',
  }

  # aptly cache dir
  file {$aptly_cache_dir:
    ensure => 'directory',
    owner  => $aptly_user,
    group  => $aptly_group,
    mode   => '0750',
  }

  # Insert hello package script
  #############################
  file {$insert_hello_script:
    ensure => 'file',
    owner  => $aptly_user,
    group  => $aptly_group,
    mode   => '0750',
    source => 'puppet:///modules/aptly_profile/initialize_hello_repository.sh',
  }

  # Repo Singing Key management
  #############################

  # Mostly copy-paste from `keypair::gpg_keypair`
  # We can't use the `keypair::gpg_keypair` defined type, because we need access
  # to the $key variable to create our `apt::key` resource

  include ::keypair::gpg # To make the parent directory
  $basename = '/etc/gpg_keys/aptly'

  $existing_key = get_first_matching_value($::gpg_keys, {
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
