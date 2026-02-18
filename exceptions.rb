# frozen_string_literal: true

module Exceptions
  # Base exception class for all CI/CD errors
  class CICDError < StandardError; end

  # Configuration and validation errors
  class ConfigurationError < CICDError; end

  class EmptyUrlException < ConfigurationError
    def initialize(msg = "Repository URL is required but was not provided or is empty. Please supply a valid git repository URL (e.g., 'https://github.com/user/repo.git').")
      super(msg)
    end
  end

  class InvalidUrlException < ConfigurationError
    def initialize(url, msg = nil)
      msg ||= "Invalid repository URL: '#{url}'. URL must start with http://, https://, or git@"
      super(msg)
    end
  end

  class EmptyBuildCommandException < ConfigurationError
    def initialize(msg = "Build command is required but was not provided or is empty. Please supply a valid build command (e.g., 'npm install && npm test').")
      super(msg)
    end
  end

  class EmptyDeployCommandException < ConfigurationError
    def initialize(msg = "Deploy command is required but was not provided or is empty. Please supply a valid deploy command (e.g., 'npm run deploy').")
      super(msg)
    end
  end

  # Execution errors
  class ExecutionError < CICDError
    attr_reader :command, :exit_status, :output

    def initialize(command, exit_status, output, msg = nil)
      @command = command
      @exit_status = exit_status
      @output = output
      msg ||= "Command failed with exit status #{exit_status}"
      super(msg)
    end
  end

  class PullFailException < ExecutionError
    def initialize(url, exit_status, output)
      super(
        "git clone #{url}",
        exit_status,
        output,
        "Failed to clone repository from '#{url}'. Exit status: #{exit_status}. Verify the URL is correct, the repository exists, and you have access permissions."
      )
    end
  end

  class BuildException < ExecutionError
    def initialize(command, exit_status, output)
      super(
        command,
        exit_status,
        output,
        "Build command '#{command}' failed with exit status #{exit_status}. Check the build output for errors and ensure all dependencies are installed."
      )
    end
  end

  class DeployException < ExecutionError
    def initialize(command, exit_status, output)
      super(
        command,
        exit_status,
        output,
        "Deploy command '#{command}' failed with exit status #{exit_status}. Check the deploy output for errors."
      )
    end
  end

  # Sandbox errors
  class SandboxError < CICDError; end

  class SandboxTimeoutError < SandboxError
    def initialize(timeout, msg = nil)
      msg ||= "Command exceeded timeout limit of #{timeout} seconds and was terminated."
      super(msg)
    end
  end

  class SandboxSetupError < SandboxError
    def initialize(msg = 'Failed to set up sandbox environment.')
      super(msg)
    end
  end

  # Network and resource errors
  class NetworkError < CICDError; end

  class RequestTooLargeError < CICDError
    def initialize(size, max_size)
      super("Request body size (#{size} bytes) exceeds maximum allowed size (#{max_size} bytes).")
    end
  end
end
