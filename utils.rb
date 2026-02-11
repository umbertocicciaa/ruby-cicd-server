require 'fileutils'
require_relative 'logging'

module Utils
  def self.prepare_directory(directory)
    if Dir.exist?(directory.to_s)
        Logging.debug("Removing existing directory: #{directory}")
        FileUtils.rm_rf(directory.to_s)
    end
    Logging.debug("Creating directory: #{directory}")
    Dir.mkdir(directory.to_s)
  end

  def self.create_and_enter_directory(directory)
    Logging.debug("Creating and entering directory: #{directory}")
    Dir.mkdir(directory.to_s)
    Dir.chdir(directory.to_s)
  end

  def self.change_directory(directory)
    Logging.debug("Changing directory to: #{directory}")
    Dir.chdir(directory.to_s)
  end
  
  def self.clean_directory(directory)
    if Dir.exist?(directory.to_s)
        Logging.debug("Cleaning directory: #{directory}")
        FileUtils.rm_rf(directory.to_s)
    end
  end
end