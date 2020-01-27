# @summary configure apache for aptly
#
# @param docroot Document root
# @param force_https_reverse_proxy Force rewrite to https using X-Forwarded-proto
# @param enable_api Enable configuration for the aptly api
# @param api_vhost Vhost to run the api on. Can not be aptly. Used when proxy_api is enabled.
# @param proxy_api Put a reverse proxy between the api using apache. Adds authentication support.
# @param api_listen address the api is listening on
# @param proxy_api_htpasswd_users Protect the api, allow these users.
class aptly_profile::apache (
  Stdlib::Absolutepath $docroot,
  Boolean $force_https_reverse_proxy,
  Boolean $enable_api,
  String $api_vhost,
  Boolean $proxy_api,
  String $api_listen,
  Hash $proxy_api_htpasswd_users,
) {

  assert_private()

  class {'::apache':
    default_vhost => false,
    default_mods  => false,
  }

  include '::apache::mod::dir'
  include '::apache::mod::autoindex'

  if $force_https_reverse_proxy {
    include '::apache::mod::rewrite'
    $https_rewrite_rules = [{
      'comment'      => 'Force https redirect for proxied requests (loadbalancer)',
      'rewrite_cond' => ['%{HTTP:X-Forwarded-Proto} =http'],
      'rewrite_rule' => ['. https://%{HTTP:Host}%{REQUEST_URI} [L,R=permanent]'],
    }, ]
  }
  else {
    $https_rewrite_rules = []
  }

  ::apache::vhost {'aptly':
    port           => 80,
    docroot        => $docroot,
    manage_docroot => false,
    rewrites       => $https_rewrite_rules,
    require        => File[$docroot],
  }

  if $enable_api and $proxy_api {
    include ::apache::mod::auth_basic
    include ::apache::mod::authn_core
    include ::apache::mod::authn_file
    include ::apache::mod::authz_user

    $content = @(EOF)
      <% $users.each |$usr, $pwd| { -%>
      <%= $usr %>:<%= $pwd %>
      <% } -%>
      | EOF

    file {'/var/www/.aptly-api-passwdfile':
      ensure  => file,
      content => inline_epp($content, {'users' => $proxy_api_htpasswd_users} ),
      require => Class['Apache'],
    }

    ::apache::vhost {$api_vhost:
      priority       => 50,
      port           => 80,
      manage_docroot => false,
      proxy_pass     => [
        {
          'path' => '/',
          'url'  => "http://${api_listen}/"
        },
      ],
      docroot        => '/var/www/html',
      rewrites       => $https_rewrite_rules,
      directories    => [
        {
          'provider'            => 'location',
          'path'                => '/',
          'auth_type'           => 'Basic',
          'auth_name'           => 'api-access',
          'auth_basic_provider' => 'file',
          'auth_user_file'      => '/var/www/.aptly-api-passwdfile',
          'auth_require'        => 'valid-user',
        },
      ],
      require        => [File[$docroot], Apache::Vhost['aptly']],
    }
  }
}
