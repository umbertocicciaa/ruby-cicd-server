# frozen_string_literal: true

# Use Ruby's built-in Coverage module (no external gems)
require 'coverage'

# Start coverage tracking BEFORE loading any application code
SOURCE_DIR = File.expand_path('..', __dir__)
Coverage.start

# Register an at_exit hook to print coverage report
at_exit do
  results = Coverage.result

  # Filter to only our project files
  project_files = %w[constants.rb exceptions.rb executor.rb logging.rb monitoring.rb
                     namespace_sandbox.rb server.rb utils.rb]

  total_lines = 0
  covered_lines = 0
  uncovered_details = []

  project_files.each do |filename|
    filepath = File.join(SOURCE_DIR, filename)
    coverage_data = results[filepath]
    next unless coverage_data

    file_lines = coverage_data.compact
    file_total = file_lines.size
    file_covered = file_lines.count { |hits| hits > 0 }
    file_pct = file_total > 0 ? ((file_covered.to_f / file_total) * 100).round(1) : 0.0

    total_lines += file_total
    covered_lines += file_covered

    uncovered = coverage_data.each_with_index
                             .select { |hits, _| hits == 0 }
                             .map { |_, idx| idx + 1 }

    uncovered_details << { file: filename, total: file_total, covered: file_covered,
                           pct: file_pct, uncovered_lines: uncovered }
  end

  overall_pct = total_lines > 0 ? ((covered_lines.to_f / total_lines) * 100).round(1) : 0.0

  puts "\n#{'=' * 70}"
  puts 'COVERAGE REPORT (Ruby built-in Coverage module)'
  puts '=' * 70
  printf "%-28s %8s %8s %8s\n", 'File', 'Lines', 'Covered', 'Coverage'
  puts '-' * 70

  uncovered_details.sort_by { |d| d[:pct] }.each do |d|
    printf "%-28s %8d %8d %7.1f%%\n", d[:file], d[:total], d[:covered], d[:pct]
    puts "    uncovered lines: #{d[:uncovered_lines].join(', ')}" unless d[:uncovered_lines].empty?
  end

  puts '-' * 70
  printf "%-28s %8d %8d %7.1f%%\n", 'TOTAL', total_lines, covered_lines, overall_pct
  puts '=' * 70

  if overall_pct < 90.0
    puts "WARNING: Coverage #{overall_pct}% is below 90% target"
  else
    puts "OK: Coverage #{overall_pct}% meets 90% target"
  end
end

require 'minitest/autorun'
require 'stringio'
require 'tmpdir'
require 'fileutils'
require 'json'

# Now load application code (after Coverage.start)
require_relative '../constants'
require_relative '../exceptions'
require_relative '../logging'
require_relative '../monitoring'
require_relative '../utils'
require_relative '../server'
require_relative '../executor'
require_relative '../namespace_sandbox'
