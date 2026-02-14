require_relative 'core'
require_relative 'logging'
require_relative 'namespace_sandbox'

module Executor
  def self.execution(url, build, deploy)
    Logging.step("CI/CD Pipeline Started")
    Logging.info("URL: #{url || '(not provided)'}")
    Logging.info("Build command: #{build || '(not provided)'}")
    Logging.info("Deploy command: #{deploy || '(not provided)'}")

    container = nil
    
    begin
      Logging.timed("full pipeline") do
        NamespaceSandbox.with_container do |cont|
          container = cont
          
          if url
            Logging.step("Pulling code from repository")
            result = container.run("git clone #{url} repo")
            
            if result[:success]
              Logging.success("Code pulled successfully")
            else
              raise "Failed to pull code: #{result[:stderr] || result[:output]}"
            end
          end
          
          if build
            Logging.step("Executing build command")
            build_cmd = url ? "cd repo && #{build}" : build
            result = container.run(build_cmd)
            
            if result[:success]
              Logging.success("Build completed successfully")
              Logging.debug(result[:output]) unless result[:output].empty?
            else
              raise "Build failed: #{result[:stderr] || result[:output]}"
            end
          end
          
          if deploy
            Logging.step("Executing deploy command")
            deploy_cmd = url ? "cd repo && #{deploy}" : deploy
            result = container.run(deploy_cmd)
            
            if result[:success]
              Logging.success("Deploy completed successfully")
              Logging.debug(result[:output]) unless result[:output].empty?
            else
              raise "Deploy failed: #{result[:stderr] || result[:output]}"
            end
          end
        end
      end
      
      Logging.step("CI/CD Pipeline Finished Successfully")
      return "Success"
      
    rescue StandardError => e
      Logging.error("Pipeline failed: #{e.class} — #{e.message}")
      Logging.debug(e.backtrace&.join("\n"))
      return "Error: #{e.message}"
    end
  end
end