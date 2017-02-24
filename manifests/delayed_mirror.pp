# Create a delayed mirror.
#
# A delayed mirror is not created immediately but when the aptly-update script runs.
# We create config files in the mirror.d configuration directory that are picked up
# by aptly-update.rb before publishing anything
#
# @param config The config hash. Options are compatible with the upstream aptly::mirror definition.
define aptly_profile::delayed_mirror(
  Hash $config,
) {

  $yaml_name = regsubst($name, '/', '__', 'G')

  $config_defaults = $::aptly_profile::mirror_defaults
  $config_hash = merge($config_defaults, $config)

  file {"${::aptly_profile::mirror_d}/${yaml_name}.yaml":
    ensure  => 'file',
    owner   => $::aptly_profile::aptly_user,
    group   => $::aptly_profile::aptly_group,
    content => inline_template('<%= @config_hash.to_hash.to_yaml %>'),
  }

}
