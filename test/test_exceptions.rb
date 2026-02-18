# frozen_string_literal: true

require_relative 'test_helper'

class TestExceptions < Minitest::Test
  # --- CICDError ---
  def test_cicd_error_is_standard_error
    assert Exceptions::CICDError < StandardError
  end

  # --- ConfigurationError ---
  def test_configuration_error_is_cicd_error
    assert Exceptions::ConfigurationError < Exceptions::CICDError
  end

  # --- EmptyUrlException ---
  def test_empty_url_exception_default_message
    e = Exceptions::EmptyUrlException.new
    assert_match(/Repository URL is required/, e.message)
  end

  def test_empty_url_exception_is_configuration_error
    assert Exceptions::EmptyUrlException < Exceptions::ConfigurationError
  end

  # --- InvalidUrlException ---
  def test_invalid_url_exception_default_message
    e = Exceptions::InvalidUrlException.new('bad-url')
    assert_match(/Invalid repository URL/, e.message)
    assert_match(/bad-url/, e.message)
  end

  def test_invalid_url_exception_custom_message
    e = Exceptions::InvalidUrlException.new('x', 'custom msg')
    assert_equal 'custom msg', e.message
  end

  # --- EmptyBuildCommandException ---
  def test_empty_build_command_exception_default_message
    e = Exceptions::EmptyBuildCommandException.new
    assert_match(/Build command is required/, e.message)
  end

  # --- EmptyDeployCommandException ---
  def test_empty_deploy_command_exception_default_message
    e = Exceptions::EmptyDeployCommandException.new
    assert_match(/Deploy command is required/, e.message)
  end

  # --- ExecutionError ---
  def test_execution_error_attributes
    e = Exceptions::ExecutionError.new('ls -la', 1, 'no such file')
    assert_equal 'ls -la', e.command
    assert_equal 1, e.exit_status
    assert_equal 'no such file', e.output
    assert_match(/exit status 1/, e.message)
  end

  def test_execution_error_custom_message
    e = Exceptions::ExecutionError.new('cmd', 2, 'out', 'custom')
    assert_equal 'custom', e.message
  end

  def test_execution_error_is_cicd_error
    assert Exceptions::ExecutionError < Exceptions::CICDError
  end

  # --- PullFailException ---
  def test_pull_fail_exception
    e = Exceptions::PullFailException.new('https://github.com/repo.git', 128, 'fatal error')
    assert_match(/Failed to clone/, e.message)
    assert_equal 'git clone https://github.com/repo.git', e.command
    assert_equal 128, e.exit_status
    assert_equal 'fatal error', e.output
  end

  # --- BuildException ---
  def test_build_exception
    e = Exceptions::BuildException.new('make build', 2, 'compile error')
    assert_match(/Build command.*failed/, e.message)
    assert_equal 'make build', e.command
    assert_equal 2, e.exit_status
    assert_equal 'compile error', e.output
  end

  # --- DeployException ---
  def test_deploy_exception
    e = Exceptions::DeployException.new('deploy.sh', 1, 'deploy failed')
    assert_match(/Deploy command.*failed/, e.message)
    assert_equal 'deploy.sh', e.command
    assert_equal 1, e.exit_status
    assert_equal 'deploy failed', e.output
  end

  # --- SandboxError ---
  def test_sandbox_error_is_cicd_error
    assert Exceptions::SandboxError < Exceptions::CICDError
  end

  # --- SandboxTimeoutError ---
  def test_sandbox_timeout_error_default
    e = Exceptions::SandboxTimeoutError.new(60)
    assert_match(/timeout limit of 60 seconds/, e.message)
  end

  def test_sandbox_timeout_error_custom
    e = Exceptions::SandboxTimeoutError.new(60, 'custom timeout msg')
    assert_equal 'custom timeout msg', e.message
  end

  # --- SandboxSetupError ---
  def test_sandbox_setup_error_default
    e = Exceptions::SandboxSetupError.new
    assert_match(/Failed to set up sandbox/, e.message)
  end

  def test_sandbox_setup_error_custom
    e = Exceptions::SandboxSetupError.new('custom setup msg')
    assert_equal 'custom setup msg', e.message
  end

  # --- NetworkError ---
  def test_network_error_is_cicd_error
    assert Exceptions::NetworkError < Exceptions::CICDError
  end

  # --- RequestTooLargeError ---
  def test_request_too_large_error
    e = Exceptions::RequestTooLargeError.new(20_000_000, 10_000_000)
    assert_match(/20000000 bytes/, e.message)
    assert_match(/10000000 bytes/, e.message)
  end
end
