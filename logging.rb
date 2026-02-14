# frozen_string_literal: true

require 'logger'
require 'fileutils'
require_relative 'constants'

module Logging
  LOG_DIR = Config::LOGS_DIRECTORY
  LOG_FILE = File.join(LOG_DIR, Config::LOGS_FILE)

  # ANSI color codes for terminal output
  COLORS = {
    reset: "\e[0m",
    bold: "\e[1m",
    red: "\e[31m",
    green: "\e[32m",
    yellow: "\e[33m",
    blue: "\e[34m",
    magenta: "\e[35m",
    cyan: "\e[36m",
    white: "\e[37m",
    gray: "\e[90m"
  }.freeze

  class << self
    def logger
      @logger ||= create_logger
    end

    def create_logger
      FileUtils.mkdir_p(LOG_DIR) unless Dir.exist?(LOG_DIR)

      file_logger = Logger.new(
        LOG_FILE,
        Config::LOG_ROTATION_COUNT,
        Config::LOG_FILE_SIZE
      )
      
      console_logger = Logger.new($stdout)

      file_logger.level = Logger::DEBUG
      console_logger.level = Logger::INFO

      file_formatter = proc do |severity, datetime, _progname, msg|
        timestamp = datetime.strftime("%Y-%m-%d %H:%M:%S")
        "[#{timestamp}] [#{severity.ljust(5)}] #{msg}\n"
      end

      console_formatter = proc do |severity, datetime, _progname, msg|
        timestamp = datetime.strftime("%H:%M:%S")
        color = severity_color(severity)
        "#{color}[#{timestamp}] [#{severity.ljust(5)}] #{msg}#{COLORS[:reset]}\n"
      end

      file_logger.formatter = file_formatter
      console_logger.formatter = console_formatter

      MultiLogger.new(file_logger, console_logger)
    end

    def info(message)
      logger.info(message)
    end

    def debug(message)
      logger.debug(message)
    end

    def warn(message)
      logger.warn(message)
    end

    def error(message)
      logger.error(message)
    end

    def fatal(message)
      logger.fatal(message)
    end

    def success(message)
      puts "#{COLORS[:green]}#{COLORS[:bold]}✓ #{message}#{COLORS[:reset]}"
      logger.info("[SUCCESS] #{message}")
    end

    def step(message)
      separator = "=" * 60
      puts "\n#{COLORS[:blue]}#{COLORS[:bold]}#{separator}#{COLORS[:reset]}"
      puts "#{COLORS[:blue]}#{COLORS[:bold]}▶ #{message}#{COLORS[:reset]}"
      puts "#{COLORS[:blue]}#{COLORS[:bold]}#{separator}#{COLORS[:reset]}\n"
      logger.info("=== STEP: #{message} ===")
    end

    # Logs a block's execution with timing information
    def timed(label)
      start_time = Time.now
      info("Starting: #{label}")
      result = yield
      elapsed = (Time.now - start_time).round(2)
      success("Completed: #{label} (#{elapsed}s)")
      result
    rescue StandardError => e
      elapsed = (Time.now - start_time).round(2)
      error("Failed: #{label} after #{elapsed}s — #{e.class}: #{e.message}")
      raise
    end

    # Log a section with visual separation
    def section(title)
      puts "\n#{COLORS[:cyan]}#{title}#{COLORS[:reset]}"
      puts "#{COLORS[:gray]}#{'-' * title.length}#{COLORS[:reset]}"
      logger.info("--- #{title} ---")
    end

    private

    def severity_color(severity)
      case severity.to_s.upcase
      when "DEBUG"
        COLORS[:gray]
      when "INFO"
        COLORS[:cyan]
      when "WARN"
        COLORS[:yellow]
      when "ERROR", "FATAL"
        COLORS[:red]
      else
        COLORS[:reset]
      end
    end
  end

  # Broadcasts log messages to multiple Logger destinations
  class MultiLogger
    def initialize(*loggers)
      @loggers = loggers
    end

    %i[debug info warn error fatal].each do |level|
      define_method(level) do |message = nil, &block|
        @loggers.each { |logger| logger.send(level, message, &block) }
      end
    end

    def level=(level)
      @loggers.each { |logger| logger.level = level }
    end

    def close
      @loggers.each(&:close)
    end
  end
end
