# frozen_string_literal: true

require 'fileutils'
require_relative 'logging'

module Utils
  class << self
    # Prepare a directory by removing it if it exists and creating a new one
    def prepare_directory(directory)
      path = directory.to_s
      
      if Dir.exist?(path)
        Logging.debug("Removing existing directory: #{path}")
        FileUtils.rm_rf(path)
      end
      
      Logging.debug("Creating directory: #{path}")
      FileUtils.mkdir_p(path)
      
      path
    rescue => e
      Logging.error("Failed to prepare directory #{path}: #{e.message}")
      raise
    end

    # Create a directory and change into it
    def create_and_enter_directory(directory)
      path = directory.to_s
      
      Logging.debug("Creating and entering directory: #{path}")
      FileUtils.mkdir_p(path)
      Dir.chdir(path)
      
      path
    rescue => e
      Logging.error("Failed to create and enter directory #{path}: #{e.message}")
      raise
    end

    # Change to a directory
    def change_directory(directory)
      path = directory.to_s
      
      unless Dir.exist?(path)
        raise ArgumentError, "Directory does not exist: #{path}"
      end
      
      Logging.debug("Changing directory to: #{path}")
      Dir.chdir(path)
      
      path
    rescue => e
      Logging.error("Failed to change directory to #{path}: #{e.message}")
      raise
    end
    
    # Clean a directory by removing it
    def clean_directory(directory)
      path = directory.to_s
      
      if Dir.exist?(path)
        Logging.debug("Cleaning directory: #{path}")
        FileUtils.rm_rf(path)
      else
        Logging.debug("Directory does not exist, nothing to clean: #{path}")
      end
      
      true
    rescue => e
      Logging.warn("Failed to clean directory #{path}: #{e.message}")
      false
    end
    
    # Safely execute a command and return the result
    def safe_execute(command, capture_output: false)
      Logging.debug("Executing: #{command}")
      
      if capture_output
        output = `#{command} 2>&1`
        success = $?.success?
        { success: success, output: output, exit_code: $?.exitstatus }
      else
        success = system(command)
        { success: success, exit_code: $?.exitstatus }
      end
    end
    
    # Check if a command is available in the system
    def command_exists?(command)
      system("which #{command} > /dev/null 2>&1")
    end
    
    # Get the size of a directory in bytes
    def directory_size(directory)
      return 0 unless Dir.exist?(directory)
      
      total_size = 0
      Find.find(directory) do |path|
        total_size += File.size(path) if File.file?(path)
      end
      total_size
    rescue => e
      Logging.warn("Failed to calculate directory size: #{e.message}")
      0
    end
    
    # Format bytes to human-readable format
    def format_bytes(bytes)
      units = ['B', 'KB', 'MB', 'GB', 'TB']
      return '0 B' if bytes == 0
      
      exp = (Math.log(bytes) / Math.log(1024)).to_i
      exp = [exp, units.length - 1].min
      
      "%.2f %s" % [bytes.to_f / (1024 ** exp), units[exp]]
    end
    
    # Sanitize a string for use in filenames
    def sanitize_filename(filename)
      filename.to_s
        .gsub(/[^0-9A-Za-z.\-_]/, '_')
        .gsub(/_{2,}/, '_')
        .gsub(/^_|_$/, '')
    end
  end
end
