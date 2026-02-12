require_relative 'core'
require_relative 'logging'

module Executor
  def self.execution(url, build, deploy)
    Logging.step("CI/CD Pipeline Started")
    Logging.info("URL: #{url || '(not provided)'}")
    Logging.info("Build command: #{build || '(not provided)'}")
    Logging.info("Deploy command: #{deploy || '(not provided)'}")

    begin
      Logging.timed("full pipeline") do
        Core::pull_code(url)
        Core::execute(build)
        Core::deploy(deploy)
      end
      Logging.step("CI/CD Pipeline Finished Successfully")
    rescue StandardError => e
      Logging.error("Pipeline failed: #{e.class} — #{e.message}")
      Logging.debug(e.backtrace&.join("\n"))
      return e
    end
    return "Success"
  end
end
