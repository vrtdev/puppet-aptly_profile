# Creates a new publishing point with the possiblity to instantly update it.
#
# @param config Hash with configuration for the aptly-update.rb script
# @param instant_publish Boolean indicating to instantly run the aptly-update.rb script for this publishing point.
define aptly_profile::publish(
  Hash $config,
  Boolean $instant_publish = false,
) {

  $config_defaults = $::aptly_profile::publish_defaults

  ## We are using this as an escape character of a sort.
  if ($name =~ /__/) {
    fail("Double underscores are not allowed in names: ${name}")
  }

  $yaml_name = regsubst($name, '/', '__', 'G')

  $config_hash = merge($config_defaults, $config)

  file {"${::aptly_profile::publish_d}/${yaml_name}.yaml":
    ensure  => 'file',
    owner   => $::aptly_profile::aptly_user,
    group   => $::aptly_profile::aptly_group,
    content => inline_template('<%= @config_hash.to_hash.to_yaml %>'),
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
