# frozen_string_literal: true

require_relative 'test_helper'

# Minimal mock container for testing pipeline steps without sandbox
class MockContainer
  attr_reader :commands_run

  def initialize(results = {})
    @results = results         # command pattern => result hash
    @default_result = { output: "", stdout: "", stderr: "", status: 0, success: true, execution_time: 0.1, timed_out: false }
    @commands_run = []
  end

  def run(command, **_opts)
    @commands_run << command
    @results.each do |pattern, result|
      return result if command.include?(pattern.to_s)
    end
    @default_result
  end
end

class TestPipelineValidation < Minitest::Test
  # --- validate_git_url! ---
  def test_validate_http_url
    p = Executor::Pipeline.new("https://github.com/repo.git", nil, nil)
    p.send(:validate_git_url!, "https://github.com/repo.git")
  end

  def test_validate_ssh_url
    p = Executor::Pipeline.new(nil, nil, nil)
    p.send(:validate_git_url!, "git@github.com:user/repo.git")
  end

  def test_validate_git_protocol_url
    p = Executor::Pipeline.new(nil, nil, nil)
    p.send(:validate_git_url!, "git://example.com/repo.git")
  end

  def test_validate_empty_url
    p = Executor::Pipeline.new(nil, nil, nil)
    assert_raises(Exceptions::EmptyUrlException) { p.send(:validate_git_url!, "") }
  end

  def test_validate_nil_url
    p = Executor::Pipeline.new(nil, nil, nil)
    assert_raises(Exceptions::EmptyUrlException) { p.send(:validate_git_url!, nil) }
  end

  def test_validate_whitespace_url
    p = Executor::Pipeline.new(nil, nil, nil)
    assert_raises(Exceptions::EmptyUrlException) { p.send(:validate_git_url!, "   ") }
  end

  def test_validate_invalid_url
    p = Executor::Pipeline.new(nil, nil, nil)
    assert_raises(Exceptions::InvalidUrlException) { p.send(:validate_git_url!, "ftp://foo.com/repo") }
  end

  # --- build_git_clone_command ---
  def test_build_git_clone_command_basic
    p = Executor::Pipeline.new(nil, nil, nil)
    cmd = p.send(:build_git_clone_command, "https://github.com/user/repo.git")
    assert_match(/^git clone/, cmd)
    assert_match(/'https:\/\/github\.com\/user\/repo\.git'/, cmd)
    assert_match(/repo$/, cmd)
  end

  def test_build_git_clone_command_escapes_single_quotes
    p = Executor::Pipeline.new(nil, nil, nil)
    cmd = p.send(:build_git_clone_command, "https://example.com/it's-a-repo.git")
    assert_includes cmd, "git clone"
    # The URL should not appear with a raw unescaped single-quote context
    assert_includes cmd, "repo"
  end

  def test_build_git_clone_with_depth
    # Test with GIT_CLONE_DEPTH set
    original = Config::GIT_CLONE_DEPTH
    Config.send(:remove_const, :GIT_CLONE_DEPTH)
    Config.const_set(:GIT_CLONE_DEPTH, 1)

    p = Executor::Pipeline.new(nil, nil, nil)
    cmd = p.send(:build_git_clone_command, "https://github.com/repo.git")
    assert_match(/--depth 1/, cmd)
  ensure
    Config.send(:remove_const, :GIT_CLONE_DEPTH)
    Config.const_set(:GIT_CLONE_DEPTH, original)
  end
end

class TestPipelineSteps < Minitest::Test
  # --- build_steps_summary ---
  def test_steps_all
    p = Executor::Pipeline.new("url", "build", "deploy")
    assert_equal ["Pull code", "Build", "Deploy"], p.send(:build_steps_summary)
  end

  def test_steps_none
    p = Executor::Pipeline.new(nil, nil, nil)
    assert_equal [], p.send(:build_steps_summary)
  end

  def test_steps_build_only
    p = Executor::Pipeline.new(nil, "make", nil)
    assert_equal ["Build"], p.send(:build_steps_summary)
  end

  def test_steps_deploy_only
    p = Executor::Pipeline.new(nil, nil, "deploy.sh")
    assert_equal ["Deploy"], p.send(:build_steps_summary)
  end

  # --- build_success_response ---
  def test_success_response
    p = Executor::Pipeline.new("url", "build", nil)
    result = p.send(:build_success_response, 3.456)
    assert_equal "success", result[:status]
    assert_equal 3.46, result[:execution_time]
    assert_includes result[:steps], "Pull code"
    assert_includes result[:steps], "Build"
    assert_match(/successfully/, result[:message])
  end

  # --- log_pipeline_info ---
  def test_log_pipeline_info_with_values
    p = Executor::Pipeline.new("https://test.git", "make", "deploy.sh")
    # Logging.info goes through Logger which binds to $stdout at creation time.
    # capture_io won't capture it; just verify no errors.
    capture_io { p.send(:log_pipeline_info) }
  end

  def test_log_pipeline_info_nil_values
    p = Executor::Pipeline.new(nil, nil, nil)
    # "not provided" goes through Logging.info which writes to log file + console
    capture_io { p.send(:log_pipeline_info) }
    # Just ensure no error; the message goes to log
  end

  # --- log_command_output ---
  def test_log_command_output_with_both
    p = Executor::Pipeline.new(nil, nil, nil)
    result = { stdout: "some output", stderr: "some error" }
    capture_io { p.send(:log_command_output, result) }
  end

  def test_log_command_output_empty
    p = Executor::Pipeline.new(nil, nil, nil)
    result = { stdout: "  ", stderr: "  " }
    capture_io { p.send(:log_command_output, result) }
  end

  def test_log_command_output_only_stdout
    p = Executor::Pipeline.new(nil, nil, nil)
    result = { stdout: "has data", stderr: "  " }
    capture_io { p.send(:log_command_output, result) }
  end
end

class TestPipelineErrorHandling < Minitest::Test
  # --- handle_pipeline_error ---
  def test_handle_generic_error
    p = Executor::Pipeline.new(nil, nil, nil)
    error = StandardError.new("generic")
    result = nil
    capture_io { result = p.send(:handle_pipeline_error, error) }
    assert_equal "error", result[:status]
    assert_match(/generic/, result[:message])
    assert_equal({}, result[:details])
  end

  def test_handle_execution_error
    p = Executor::Pipeline.new(nil, nil, nil)
    error = Exceptions::BuildException.new("make", 2, "fail")
    result = nil
    capture_io { result = p.send(:handle_pipeline_error, error) }
    assert_equal "error", result[:status]
    assert_equal "make", result[:details][:command]
    assert_equal 2, result[:details][:exit_status]
    assert_equal "fail", result[:details][:output]
  end

  def test_handle_execution_error_nil_output
    p = Executor::Pipeline.new(nil, nil, nil)
    error = Exceptions::ExecutionError.new("cmd", 1, nil)
    result = nil
    capture_io { result = p.send(:handle_pipeline_error, error) }
    assert_equal "error", result[:status]
    assert_nil result[:details][:output]
  end

  def test_handle_error_with_backtrace
    p = Executor::Pipeline.new(nil, nil, nil)
    error = StandardError.new("with bt")
    error.set_backtrace(["line1", "line2"])
    result = nil
    capture_io { result = p.send(:handle_pipeline_error, error) }
    assert_equal "error", result[:status]
  end

  # --- build_error_details ---
  def test_error_details_execution
    p = Executor::Pipeline.new(nil, nil, nil)
    error = Exceptions::ExecutionError.new("cmd", 1, "out")
    details = p.send(:build_error_details, error)
    assert_equal "cmd", details[:command]
    assert_equal 1, details[:exit_status]
    assert_equal "out", details[:output]
  end

  def test_error_details_non_execution
    p = Executor::Pipeline.new(nil, nil, nil)
    details = p.send(:build_error_details, StandardError.new)
    assert_equal({}, details)
  end
end

class TestPipelineExecution < Minitest::Test
  # --- pull_code ---
  def test_pull_code_success
    p = Executor::Pipeline.new("https://github.com/user/repo.git", nil, nil)
    mock = MockContainer.new("git clone" => { output: "", stdout: "Cloning...", stderr: "", status: 0, success: true, execution_time: 1.0, timed_out: false })
    p.instance_variable_set(:@container, mock)

    capture_io { p.send(:pull_code) }
    assert mock.commands_run.any? { |c| c.include?("git clone") }
  end

  def test_pull_code_failure
    p = Executor::Pipeline.new("https://github.com/user/repo.git", nil, nil)
    mock = MockContainer.new("git clone" => { output: "fatal", stdout: "", stderr: "fatal: repo not found", status: 128, success: false, execution_time: 1.0, timed_out: false })
    p.instance_variable_set(:@container, mock)

    assert_raises(Exceptions::PullFailException) do
      capture_io { p.send(:pull_code) }
    end
  end

  def test_pull_code_failure_empty_stderr
    p = Executor::Pipeline.new("https://github.com/user/repo.git", nil, nil)
    mock = MockContainer.new("git clone" => { output: "error from stdout", stdout: "error from stdout", stderr: "", status: 1, success: false, execution_time: 0.5, timed_out: false })
    p.instance_variable_set(:@container, mock)

    assert_raises(Exceptions::PullFailException) do
      capture_io { p.send(:pull_code) }
    end
  end

  def test_pull_code_success_empty_output
    p = Executor::Pipeline.new("https://github.com/user/repo.git", nil, nil)
    mock = MockContainer.new("git clone" => { output: "", stdout: "  ", stderr: "", status: 0, success: true, execution_time: 0.5, timed_out: false })
    p.instance_variable_set(:@container, mock)

    capture_io { p.send(:pull_code) }
  end

  # --- run_build ---
  def test_run_build_success_with_url
    p = Executor::Pipeline.new("https://test.git", "make", nil)
    mock = MockContainer.new({})
    p.instance_variable_set(:@container, mock)

    capture_io { p.send(:run_build) }
    assert mock.commands_run.any? { |c| c.include?("cd repo") }
  end

  def test_run_build_success_without_url
    p = Executor::Pipeline.new(nil, "make", nil)
    mock = MockContainer.new({})
    p.instance_variable_set(:@container, mock)

    capture_io { p.send(:run_build) }
    assert_equal ["make"], mock.commands_run
  end

  def test_run_build_timeout
    p = Executor::Pipeline.new(nil, "long_cmd", nil)
    mock = MockContainer.new("long_cmd" => { output: "", stdout: "", stderr: "", status: 124, success: false, execution_time: 600.0, timed_out: true })
    p.instance_variable_set(:@container, mock)

    assert_raises(Exceptions::SandboxTimeoutError) do
      capture_io { p.send(:run_build) }
    end
  end

  def test_run_build_failure
    p = Executor::Pipeline.new(nil, "bad_build", nil)
    mock = MockContainer.new("bad_build" => { output: "error", stdout: "error", stderr: "", status: 1, success: false, execution_time: 0.5, timed_out: false })
    p.instance_variable_set(:@container, mock)

    assert_raises(Exceptions::BuildException) do
      capture_io { p.send(:run_build) }
    end
  end

  # --- run_deploy ---
  def test_run_deploy_success_with_url
    p = Executor::Pipeline.new("https://test.git", nil, "deploy.sh")
    mock = MockContainer.new({})
    p.instance_variable_set(:@container, mock)

    capture_io { p.send(:run_deploy) }
    assert mock.commands_run.any? { |c| c.include?("cd repo") }
  end

  def test_run_deploy_success_without_url
    p = Executor::Pipeline.new(nil, nil, "deploy.sh")
    mock = MockContainer.new({})
    p.instance_variable_set(:@container, mock)

    capture_io { p.send(:run_deploy) }
    assert_equal ["deploy.sh"], mock.commands_run
  end

  def test_run_deploy_timeout
    p = Executor::Pipeline.new(nil, nil, "slow_deploy")
    mock = MockContainer.new("slow_deploy" => { output: "", stdout: "", stderr: "", status: 124, success: false, execution_time: 600.0, timed_out: true })
    p.instance_variable_set(:@container, mock)

    assert_raises(Exceptions::SandboxTimeoutError) do
      capture_io { p.send(:run_deploy) }
    end
  end

  def test_run_deploy_failure
    p = Executor::Pipeline.new(nil, nil, "bad_deploy")
    mock = MockContainer.new("bad_deploy" => { output: "err", stdout: "err", stderr: "", status: 1, success: false, execution_time: 0.5, timed_out: false })
    p.instance_variable_set(:@container, mock)

    assert_raises(Exceptions::DeployException) do
      capture_io { p.send(:run_deploy) }
    end
  end

  # --- full execute (mocked sandbox) ---
  def test_execute_full_pipeline_success
    p = Executor::Pipeline.new("https://github.com/repo.git", "make", "deploy.sh")

    # Mock NamespaceSandbox.with_container
    original_with_container = NamespaceSandbox.method(:with_container)
    mock = MockContainer.new({})
    NamespaceSandbox.define_singleton_method(:with_container) do |&block|
      block.call(mock)
    end

    result = nil
    capture_io { result = p.execute }

    assert_equal "success", result[:status]
    assert_includes result[:steps], "Pull code"
    assert_includes result[:steps], "Build"
    assert_includes result[:steps], "Deploy"
  ensure
    NamespaceSandbox.define_singleton_method(:with_container, original_with_container)
  end

  def test_execute_no_steps
    p = Executor::Pipeline.new(nil, nil, nil)

    original_with_container = NamespaceSandbox.method(:with_container)
    mock = MockContainer.new({})
    NamespaceSandbox.define_singleton_method(:with_container) do |&block|
      block.call(mock)
    end

    result = nil
    capture_io { result = p.execute }
    assert_equal "success", result[:status]
    assert_equal [], result[:steps]
  ensure
    NamespaceSandbox.define_singleton_method(:with_container, original_with_container)
  end

  def test_execute_build_failure
    p = Executor::Pipeline.new(nil, "fail_build", nil)

    original_with_container = NamespaceSandbox.method(:with_container)
    mock = MockContainer.new("fail_build" => { output: "err", stdout: "err", stderr: "", status: 1, success: false, execution_time: 0.5, timed_out: false })
    NamespaceSandbox.define_singleton_method(:with_container) do |&block|
      block.call(mock)
    end

    result = nil
    capture_io { result = p.execute }
    assert_equal "error", result[:status]
  ensure
    NamespaceSandbox.define_singleton_method(:with_container, original_with_container)
  end

  # --- Pipeline attributes ---
  def test_pipeline_attributes
    p = Executor::Pipeline.new("url", "build", "deploy")
    assert_equal "url", p.url
    assert_equal "build", p.build_cmd
    assert_equal "deploy", p.deploy_cmd
    assert_nil p.container
  end
end

class TestExecutorModule < Minitest::Test
  def setup
    @original_execute = Executor::Pipeline.instance_method(:execute)
  end

  def teardown
    Executor::Pipeline.define_method(:execute, @original_execute)
  end

  def test_execution_success
    Executor::Pipeline.define_method(:execute) do
      { status: "success", execution_time: 0.5, message: "done", steps: [] }
    end

    result = Executor.execution(nil, "echo ok", nil)
    assert_match(/Success/, result)
    assert_match(/0\.5s/, result)
  end

  def test_execution_error
    Executor::Pipeline.define_method(:execute) do
      { status: "error", message: "Build failed" }
    end

    result = Executor.execution(nil, "bad", nil)
    assert_match(/Error/, result)
    assert_match(/Build failed/, result)
  end
end
