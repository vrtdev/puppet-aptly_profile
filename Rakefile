require 'puppetlabs_spec_helper/rake_tasks'
require 'puppet-lint/tasks/puppet-lint'
require 'rubocop/rake_task'

JENKINS_TASKS = [
  'syntax',
  'lint',
  'rubocop'
].freeze

desc 'Validate manifests, templates, and ruby files'
task :validate do
  Dir['manifests/**/*.pp'].each do |manifest|
    sh "puppet parser validate --noop #{manifest}"
  end
  Dir['spec/**/*.rb','lib/**/*.rb'].each do |ruby_file|
    sh "ruby -c #{ruby_file}" unless ruby_file =~ %r{spec/fixtures}
  end
  Dir['templates/**/*.erb'].each do |template|
    sh "erb -P -x -T '-' #{template} | ruby -c"
  end
end

namespace :jenkins do
  task :all do
    base = ENV['BUNDLE_GEMFILE'].nil? ? 'rake' : "#{ENV['BUNDLE_BIN_PATH']} exec rake"
    failed_tasks = []
    JENKINS_TASKS.each do |target|
      # puts "Executing '#{base} #{target}'"
      failed_tasks << target unless system("#{base} #{target}")
    end
    unless failed_tasks.empty?
      warn "The following targets failed: #{failed_tasks.join(', ')}"
      exit(1)
    end
  end
end

desc 'Run all jenkins tasks'
task jenkins: ['jenkins:all']

Rake::Task['default'].clear
task default: [:syntax, :lint, :rubocop, :validate]

PuppetLint.configuration.ignore_paths = ['spec/**/*.pp', 'pkg/**/*.pp', 'vendor/**/*.pp']
