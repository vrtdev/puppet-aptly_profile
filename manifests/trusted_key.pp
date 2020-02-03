# installs a given key in to the trustedkeys.gpg keyring of aptly
#
# @param key Content of the key to import.
# @param comment Comment to add with the key. Defaults to ''.
# @param gpg_path The gpg binary to use.
define aptly_profile::trusted_key(
  $key,
  $comment = '',
  $gpg_path = '/usr/bin/gpg',
) {

  exec { "aptly_profile::trusted_key import aptly GPG key ${title} (${comment}) in to keyring":
    user        => $::aptly_profile::aptly_user,
    environment => ["HOME=${::aptly_profile::aptly_homedir}"],
    cwd         => $::aptly_profile::aptly_homedir,
    command     => "/bin/echo '${key}' | ${gpg_path} --no-default-keyring --keyring trustedkeys.gpg --import",
    unless      => "${gpg_path} --no-default-keyring --keyring trustedkeys.gpg --list-keys '${title}'",
    require     => File[$::aptly_profile::aptly_homedir],
    before      => Class['::aptly'], # or he will try to download the keys, and fail
  }

}
