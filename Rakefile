# frozen_string_literal: true

require 'rake/testtask'

desc "Start the CI/CD server"
task :start do
  ruby "server.rb"
end

Rake::TestTask.new(:test) do |t|
  t.test_files = FileList['test/test_*.rb']
  t.warning = false
end

desc "Run tests with coverage report"
task :coverage do
  ruby "test/run_all.rb"
end

task default: :test
