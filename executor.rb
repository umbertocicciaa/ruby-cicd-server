# frozen_string_literal: true

require_relative 'namespace_sandbox'
require_relative 'logging'
require_relative 'exceptions'
require_relative 'monitoring'

module Executor
  class Pipeline
    attr_reader :url, :build_cmd, :deploy_cmd, :container

    def initialize(url, build_cmd, deploy_cmd)
      @url = url
      @build_cmd = build_cmd
      @deploy_cmd = deploy_cmd
      @container = nil
    end

    def execute
      Logging.step('CI/CD Pipeline Started')
      log_pipeline_info

      start_time = Time.now

      begin
        Logging.timed('full pipeline') do
          NamespaceSandbox.with_container do |cont|
            @container = cont

            pull_code if @url
            run_build if @build_cmd
            run_deploy if @deploy_cmd
          end
        end

        execution_time = Time.now - start_time
        Monitoring.record_pipeline_success(execution_time)
        Logging.step('CI/CD Pipeline Finished Successfully')

        build_success_response(execution_time)
      rescue StandardError => e
        execution_time = Time.now - start_time
        Monitoring.record_pipeline_failure(e, execution_time)
        handle_pipeline_error(e)
      end
    end

    private

    def log_pipeline_info
      Logging.info("Repository URL: #{@url || '(not provided)'}")
      Logging.info("Build command: #{@build_cmd || '(not provided)'}")
      Logging.info("Deploy command: #{@deploy_cmd || '(not provided)'}")
    end

    def pull_code
      Logging.step('Pulling code from repository')

      validate_git_url!(@url)

      clone_cmd = build_git_clone_command(@url)
      Logging.debug("Running: #{clone_cmd}")
      result = @container.run(clone_cmd, timeout: Config::GIT_TIMEOUT)

      if result[:success]
        Logging.success('Code pulled successfully')
        Logging.debug("Clone output: #{result[:stdout]}") unless result[:stdout].strip.empty?
      else
        error_output = result[:stderr].empty? ? result[:stdout] : result[:stderr]
        Logging.error("Git clone failed with exit status #{result[:status]}")
        Logging.debug("Output: #{error_output}")
        raise Exceptions::PullFailException.new(@url, result[:status], error_output)
      end
    end

    def run_build
      Logging.step('Executing build command')

      build_cmd = @url ? "cd repo && #{@build_cmd}" : @build_cmd
      result = @container.run(build_cmd)

      if result[:success]
        Logging.success("Build completed successfully in #{result[:execution_time]}s")
        log_command_output(result)
      elsif result[:timed_out]
        raise Exceptions::SandboxTimeoutError.new(Config::SANDBOX_TIMEOUT)
      else
        raise Exceptions::BuildException.new(@build_cmd, result[:status], result[:output])
      end
    end

    def run_deploy
      Logging.step('Executing deploy command')

      deploy_cmd = @url ? "cd repo && #{@deploy_cmd}" : @deploy_cmd
      result = @container.run(deploy_cmd)

      if result[:success]
        Logging.success("Deploy completed successfully in #{result[:execution_time]}s")
        log_command_output(result)
      elsif result[:timed_out]
        raise Exceptions::SandboxTimeoutError.new(Config::SANDBOX_TIMEOUT)
      else
        raise Exceptions::DeployException.new(@deploy_cmd, result[:status], result[:output])
      end
    end

    def validate_git_url!(url)
      raise Exceptions::EmptyUrlException if url.nil? || url.strip.empty?

      valid_patterns = [
        %r{^https?://},      # HTTP/HTTPS
        /^git@/,             # SSH
        %r{^git://} # Git protocol
      ]

      return if valid_patterns.any? { |pattern| url.match?(pattern) }

      raise Exceptions::InvalidUrlException.new(url)
    end

    def build_git_clone_command(url)
      # Escape URL for shell safety
      escaped_url = url.gsub("'", "'\\''")

      cmd = 'git clone'
      cmd += " --depth #{Config::GIT_CLONE_DEPTH}" if Config::GIT_CLONE_DEPTH
      cmd += " '#{escaped_url}' repo"
      cmd
    end

    def log_command_output(result)
      Logging.debug("STDOUT:\n#{result[:stdout]}") unless result[:stdout].strip.empty?

      return if result[:stderr].strip.empty?

      Logging.debug("STDERR:\n#{result[:stderr]}")
    end

    def build_success_response(execution_time)
      {
        status: 'success',
        message: 'CI/CD Pipeline completed successfully',
        execution_time: execution_time.round(2),
        steps: build_steps_summary
      }
    end

    def build_steps_summary
      steps = []
      steps << 'Pull code' if @url
      steps << 'Build' if @build_cmd
      steps << 'Deploy' if @deploy_cmd
      steps
    end

    def handle_pipeline_error(error)
      Logging.error("Pipeline failed: #{error.class} — #{error.message}")

      if error.is_a?(Exceptions::ExecutionError)
        Logging.debug("Command: #{error.command}")
        Logging.debug("Exit status: #{error.exit_status}")
        Logging.debug("Output: #{error.output}") if error.output
      end

      Logging.debug(error.backtrace&.join("\n")) if error.backtrace

      {
        status: 'error',
        error: error.class.name,
        message: error.message,
        details: build_error_details(error)
      }
    end

    def build_error_details(error)
      details = {}

      if error.is_a?(Exceptions::ExecutionError)
        details[:command] = error.command
        details[:exit_status] = error.exit_status
        details[:output] = error.output if error.output
      end

      details
    end
  end

  # Main execution entry point
  def self.execution(url, build, deploy)
    pipeline = Pipeline.new(url, build, deploy)
    result = pipeline.execute

    # Return serializable result
    if result[:status] == 'success'
      "Success: Pipeline completed in #{result[:execution_time]}s"
    else
      "Error: #{result[:message]}"
    end
  end
end
