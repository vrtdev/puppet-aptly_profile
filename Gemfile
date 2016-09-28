source 'https://rubygems.org'

puppetversion = ENV.key?('PUPPET_VERSION') ? (ENV['PUPPET_VERSION']).to_s : ['>= 3.3']
gem 'puppet', puppetversion
gem 'puppet-lint', '>= 1.0.0'
gem 'facter', '>= 2.4'

gem 'rake'
gem 'puppetlabs_spec_helper'
gem 'rubocop'

group :development do
  gem 'awesome_print'
end
