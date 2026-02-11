require_relative 'utils.rb'
require_relative 'constants.rb'
require_relative 'exceptions.rb'
require_relative 'logging.rb'

module Core 
  def self.pull_code(url)
    Logging.step("Pull Code")
    raise Exceptions::EmptyUrlException if url.nil? || url.empty?  
    Logging.info("Cloning repository from '#{url}' into '#{REPOSITORY_DESTINATION}'")
    Utils::prepare_directory(REPOSITORY_DESTINATION.to_s)
    Logging.timed("git clone") do
      result = system("git clone #{url} #{REPOSITORY_DESTINATION.to_s}")
      raise Exceptions::PullFailException, "Failed to clone repository from '#{url}' into '#{REPOSITORY_DESTINATION}'. Verify that the URL is correct, the repository exists, and you have the necessary access permissions." unless result
    end
    Logging.info("Repository cloned successfully")
  end
  
  def self.execute(build)
    Logging.step("Build")
    raise Exceptions::EmptyBuildCommandException if build.nil? || build.empty?
    Logging.info("Running build command: '#{build}'")
    Utils::change_directory(REPOSITORY_DESTINATION.to_s)
    Logging.timed("build execution") do
      result = system("#{build}")
      raise Exceptions::BuildException, "Build command '#{build}' failed with a non-zero exit status in directory '#{Dir.pwd}'. Check the build output above for errors and ensure all dependencies are installed." unless result
    end
    Logging.info("Build completed successfully")
  end
  
  def self.deploy()
    Logging.step("Deploy")
    Logging.warn("Deploy step is not yet implemented")
  end
end
