# frozen_string_literal: true

require 'rake/testtask'

desc 'Run unit tests (excludes integration tests that require Stockfish)'
Rake::TestTask.new do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/*_test.rb'].exclude('test/integration/**/*')
  t.verbose = true
end

desc 'Run integration tests (requires Stockfish engine)'
Rake::TestTask.new(:integration) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/integration/**/*_test.rb']
  t.verbose = true
end

task default: %i[test]
