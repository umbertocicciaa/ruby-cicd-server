# frozen_string_literal: true

require_relative 'test_helper'

class TestConstants < Minitest::Test
  def test_repository_destination
    assert_equal "repository_cloned", Config::REPOSITORY_DESTINATION
  end

  def test_logs_directory
    assert_equal "logs", Config::LOGS_DIRECTORY
  end

  def test_logs_file
    assert_equal "cicd.log", Config::LOGS_FILE
  end

  def test_sandbox_timeout
    assert_equal 600, Config::SANDBOX_TIMEOUT
  end

  def test_sandbox_cpu_limit
    assert_equal 600, Config::SANDBOX_CPU_LIMIT
  end

  def test_sandbox_memory_limit
    assert_equal 2 * 1024 * 1024, Config::SANDBOX_MEMORY_LIMIT
  end

  def test_sandbox_process_limit
    assert_equal 50, Config::SANDBOX_PROCESS_LIMIT
  end

  def test_sandbox_file_size_limit
    assert_equal 100 * 1024, Config::SANDBOX_FILE_SIZE_LIMIT
  end

  def test_server_port_default
    assert_kind_of Integer, Config::SERVER_PORT
  end

  def test_server_host_default
    assert_kind_of String, Config::SERVER_HOST
  end

  def test_max_request_size
    assert_equal 10 * 1024 * 1024, Config::MAX_REQUEST_SIZE
  end

  def test_log_rotation_count
    assert_equal 5, Config::LOG_ROTATION_COUNT
  end

  def test_log_file_size
    assert_equal 1_048_576, Config::LOG_FILE_SIZE
  end

  def test_git_timeout
    assert_equal 300, Config::GIT_TIMEOUT
  end
end
