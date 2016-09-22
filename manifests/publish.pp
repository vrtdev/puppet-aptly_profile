#
#
#
define aptly_profile::publish(
  Hash $config,
  String $order = '10',
  Boolean $instant_publish = false,
) {

  file {"${::aptly_profile::publish_d}/${name}.yaml":
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
        "${::aptly_profile::publish_d}/${name}.yaml",
      ],
      subscribe   => File["${::aptly_profile::publish_d}/${name}.yaml"],
    }
  }

}
