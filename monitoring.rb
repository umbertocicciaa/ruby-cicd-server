# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative 'constants'

module Monitoring
  METRICS_DIR = File.join(Config::LOGS_DIRECTORY, 'metrics')
  METRICS_FILE = File.join(METRICS_DIR, 'pipeline_metrics.json')

  class Metrics
    attr_accessor :total_runs, :successful_runs, :failed_runs,
                  :total_execution_time, :errors

    def initialize
      @total_runs = 0
      @successful_runs = 0
      @failed_runs = 0
      @total_execution_time = 0.0
      @errors = Hash.new(0) # Error type => count
    end

    def average_execution_time
      return 0 if @total_runs.zero?

      (@total_execution_time / @total_runs).round(2)
    end

    def success_rate
      return 0 if @total_runs.zero?

      ((@successful_runs.to_f / @total_runs) * 100).round(2)
    end

    def to_h
      {
        total_runs: @total_runs,
        successful_runs: @successful_runs,
        failed_runs: @failed_runs,
        total_execution_time: @total_execution_time.round(2),
        average_execution_time: average_execution_time,
        success_rate: success_rate,
        errors: @errors
      }
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

    def self.from_hash(hash)
      metrics = new
      metrics.total_runs = hash['total_runs'] || 0
      metrics.successful_runs = hash['successful_runs'] || 0
      metrics.failed_runs = hash['failed_runs'] || 0
      metrics.total_execution_time = hash['total_execution_time'] || 0.0
      errors = hash['errors'] || {}
      metrics.errors = Hash.new(0).merge(errors)
      metrics
    end
  end

  class << self
    def record_pipeline_success(execution_time)
      with_metrics do |metrics|
        metrics.total_runs += 1
        metrics.successful_runs += 1
        metrics.total_execution_time += execution_time
      end
    end

    def record_pipeline_failure(error, execution_time)
      with_metrics do |metrics|
        metrics.total_runs += 1
        metrics.failed_runs += 1
        metrics.total_execution_time += execution_time

        error_type = error.class.name
        metrics.errors[error_type] += 1
      end
    end

    def get_metrics
      load_metrics
    end

    def reset_metrics!
      FileUtils.rm_f(METRICS_FILE) if File.exist?(METRICS_FILE)
      Metrics.new
    end

    def print_summary
      metrics = get_metrics

      puts "\n" + '=' * 60
      puts 'Pipeline Metrics Summary'
      puts '=' * 60
      puts "Total runs:           #{metrics.total_runs}"
      puts "Successful runs:      #{metrics.successful_runs}"
      puts "Failed runs:          #{metrics.failed_runs}"
      puts "Success rate:         #{metrics.success_rate}%"
      puts "Avg execution time:   #{metrics.average_execution_time}s"
      puts "Total execution time: #{metrics.total_execution_time.round(2)}s"

      unless metrics.errors.empty?
        puts "\nError breakdown:"
        metrics.errors.each do |error_type, count|
          puts "  #{error_type}: #{count}"
        end
      end

      puts '=' * 60 + "\n"
    end

    private

    def with_metrics
      metrics = load_metrics
      yield metrics
      save_metrics(metrics)
    end

    def load_metrics
      return Metrics.new unless File.exist?(METRICS_FILE)

      begin
        data = JSON.parse(File.read(METRICS_FILE))
        Metrics.from_hash(data)
      rescue JSON::ParserError, Errno::ENOENT
        Metrics.new
      end
    end

    def save_metrics(metrics)
      FileUtils.mkdir_p(METRICS_DIR) unless Dir.exist?(METRICS_DIR)

      File.write(METRICS_FILE, JSON.pretty_generate(metrics.to_h))
    rescue StandardError => e
      warn "Warning: Failed to save metrics: #{e.message}"
    end
  end
end
