# Creates a new publishing point with the possiblity to instantly update it.
#
# @param config Hash with configuration for the aptly-update.rb script
# @param instant_publish Boolean indicating to instantly run the aptly-update.rb script for this publishing point.
define aptly_profile::publish(
  Hash $config,
  Boolean $instant_publish = false,
) {

  ## We are using this as an escape character of a sort.
  validate_re($name, '__', 'Double underscores are not allowed in names')

  $yaml_name = regsubst($name, '/', '__', 'G')

  file {"${::aptly_profile::publish_d}/${yaml_name}.yaml":
    ensure  => 'file',
    owner   => $::aptly_profile::aptly_user,
    group   => $::aptly_profile::aptly_group,
    content => inline_template('<%= @config.to_hash.to_yaml %>'),
  }

  if $instant_publish {
    exec {"aptly_profile::publish: instant-publish ${name}":
      refreshonly => true,
      command     => "${::aptly_profile::aptly_homedir}/aptly-update.rb '${name}'",
      user        => $::aptly_profile::aptly_user,
      group       => $::aptly_profile::aptly_group,
      environment => $::aptly_profile::aptly_environment,
      cwd         => $::aptly_profile::aptly_homedir,
      require     => File[
        "${::aptly_profile::aptly_homedir}/aptly-update.rb",
        "${::aptly_profile::publish_d}/${yaml_name}.yaml",
      ],
      subscribe   => File["${::aptly_profile::publish_d}/${name}.yaml"],
    }
  }

}
