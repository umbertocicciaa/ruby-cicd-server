require 'logger'
require 'fileutils'
require_relative 'constants'

module Logging
  LOG_DIR = LOGS_DIRECTORY
  LOG_FILE = File.join(LOG_DIR, LOGS_FILE)

  def self.logger
    @logger ||= create_logger
  end

  def self.create_logger
    FileUtils.mkdir_p(LOG_DIR) unless Dir.exist?(LOG_DIR)

    file_logger = Logger.new(LOG_FILE, 5, 1_048_576) # 5 rotated files, 1MB each
    console_logger = Logger.new($stdout)

    file_logger.level = Logger::DEBUG
    console_logger.level = Logger::INFO

    formatter = proc do |severity, datetime, _progname, msg|
      timestamp = datetime.strftime("%Y-%m-%d %H:%M:%S")
      "[#{timestamp}] [#{severity.ljust(5)}] #{msg}\n"
    end

    file_logger.formatter = formatter
    console_logger.formatter = formatter

    MultiLogger.new(file_logger, console_logger)
  end

  def self.info(message)
    logger.info(message)
  end

  def self.debug(message)
    logger.debug(message)
  end

  def self.warn(message)
    logger.warn(message)
  end

  def self.error(message)
    logger.error(message)
  end

  def self.fatal(message)
    logger.fatal(message)
  end

  def self.step(message)
    separator = "=" * 50
    logger.info(separator)
    logger.info("STEP: #{message}")
    logger.info(separator)
  end

  # Logs a block's execution with timing information
  def self.timed(label)
    start_time = Time.now
    info("Starting: #{label}")
    result = yield
    elapsed = (Time.now - start_time).round(2)
    info("Completed: #{label} (#{elapsed}s)")
    result
  rescue StandardError => e
    elapsed = (Time.now - start_time).round(2)
    error("Failed: #{label} after #{elapsed}s — #{e.class}: #{e.message}")
    raise
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
