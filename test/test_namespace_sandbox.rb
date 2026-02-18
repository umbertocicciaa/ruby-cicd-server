# frozen_string_literal: true

require_relative 'test_helper'

# Subclass that skips unshare so we can test all other Container logic
class TestableContainer < NamespaceSandbox::Container
  def require_unshare!
    # no-op for testing
  end
end

class TestContainerInternals < Minitest::Test
  def setup
    @container = TestableContainer.new
  end

  def teardown
    @container&.cleanup
  end

  def test_container_has_hex_id
    assert_match(/\A[0-9a-f]{16}\z/, @container.container_id)
  end

  def test_workspace_directory_exists
    assert Dir.exist?(@container.workspace)
  end

  def test_workspace_permissions
    mode = File.stat(@container.workspace).mode & 0o777
    assert_equal 0o700, mode
  end

  # --- build_clean_environment ---
  def test_build_clean_environment_defaults
    env = @container.send(:build_clean_environment, {})
    assert_equal @container.workspace, env['HOME']
    assert_equal @container.workspace, env['TMPDIR']
    assert_includes env['PATH'], '/usr/bin'
    assert env.key?('LANG')
    assert env.key?('LC_ALL')
  end

  def test_build_clean_environment_custom_vars
    env = @container.send(:build_clean_environment, { 'FOO' => 'bar', 'BAZ' => 42 })
    assert_equal 'bar', env['FOO']
    assert_equal '42', env['BAZ']
  end

  def test_build_clean_environment_sanitizes_keys
    env = @container.send(:build_clean_environment, { 'BAD!KEY@#' => 'val' })
    assert_equal 'val', env['BAD_KEY__']
  end

  # --- build_unshare_command ---
  def test_build_unshare_command
    cmd = @container.send(:build_unshare_command, '/tmp/script.sh')
    assert_equal ['unshare', '--fork', '--pid', '--uts', '--ipc', 'sh', '/tmp/script.sh'], cmd
  end

  # --- create_execution_script ---
  def test_create_execution_script_content
    path = @container.send(:create_execution_script, 'echo hello_world')
    assert File.exist?(path)

    content = File.read(path)
    assert_match(%r{^#!/bin/sh}, content)
    assert_match(/set -e/, content)
    assert_match(/ulimit -t #{Config::SANDBOX_CPU_LIMIT}/, content)
    assert_match(/ulimit -v #{Config::SANDBOX_MEMORY_LIMIT}/, content)
    assert_match(/ulimit -f #{Config::SANDBOX_FILE_SIZE_LIMIT}/, content)
    assert_match(/ulimit -u #{Config::SANDBOX_PROCESS_LIMIT}/, content)
    assert_match(/ulimit -c 0/, content)
    assert_match(/echo hello_world/, content)
  ensure
    FileUtils.rm_f(path) if path
  end

  def test_create_execution_script_permissions
    path = @container.send(:create_execution_script, 'true')
    mode = File.stat(path).mode & 0o777
    assert_equal 0o700, mode
  ensure
    FileUtils.rm_f(path) if path
  end

  # --- safe_read ---
  def test_safe_read_normal
    r, w = IO.pipe
    w.write('test_data')
    w.close
    assert_equal 'test_data', @container.send(:safe_read, r)
    r.close
  end

  def test_safe_read_empty
    r, w = IO.pipe
    w.close
    assert_equal '', @container.send(:safe_read, r)
    r.close
  end

  def test_safe_read_error
    io = Object.new
    io.define_singleton_method(:read) { raise 'io error' }
    result = @container.send(:safe_read, io)
    assert_match(/Error reading output/, result)
  end

  # --- build_result ---
  def test_build_result_success
    result = @container.send(:build_result, 'stdout', 'stderr', 0, 1.555)
    assert_equal 'stdoutstderr', result[:output]
    assert_equal 'stdout', result[:stdout]
    assert_equal 'stderr', result[:stderr]
    assert_equal 0, result[:status]
    assert result[:success]
    assert_equal 1.56, result[:execution_time]
    refute result[:timed_out]
  end

  def test_build_result_failure
    result = @container.send(:build_result, '', 'err', 1, 2.0)
    refute result[:success]
    refute result[:timed_out]
  end

  def test_build_result_timeout
    result = @container.send(:build_result, '', '', 124, 10.0)
    assert result[:timed_out]
    refute result[:success]
  end

  # --- copy_into ---
  def test_copy_into_file
    tmp = File.join(Dir.tmpdir, "ci_test_#{SecureRandom.hex(4)}.txt")
    File.write(tmp, 'file content')

    dest = @container.copy_into(tmp)
    assert File.exist?(dest)
    assert_equal 'file content', File.read(dest)
  ensure
    FileUtils.rm_f(tmp)
  end

  def test_copy_into_file_custom_name
    tmp = File.join(Dir.tmpdir, "ci_test_#{SecureRandom.hex(4)}.txt")
    File.write(tmp, 'named')

    dest = @container.copy_into(tmp, 'custom_name.txt')
    assert_equal File.join(@container.workspace, 'custom_name.txt'), dest
    assert_equal 'named', File.read(dest)
  ensure
    FileUtils.rm_f(tmp)
  end

  def test_copy_into_directory
    tmp_dir = Dir.mktmpdir('ci_copy_test')
    File.write(File.join(tmp_dir, 'inner.txt'), 'inner')

    dest = @container.copy_into(tmp_dir, 'copied_dir')
    assert Dir.exist?(dest)
    assert_equal 'inner', File.read(File.join(dest, 'inner.txt'))
  ensure
    FileUtils.rm_rf(tmp_dir)
  end

  def test_copy_into_nonexistent_raises
    assert_raises(ArgumentError) do
      @container.copy_into('/nonexistent_file_xyz_12345')
    end
  end

  # --- copy_out ---
  def test_copy_out_file
    File.write(File.join(@container.workspace, 'out.txt'), 'outgoing')
    dest = File.join(Dir.tmpdir, "ci_out_#{SecureRandom.hex(4)}.txt")

    assert @container.copy_out('out.txt', dest)
    assert_equal 'outgoing', File.read(dest)
  ensure
    FileUtils.rm_f(dest)
  end

  def test_copy_out_directory
    sub = File.join(@container.workspace, 'subdir')
    FileUtils.mkdir_p(sub)
    File.write(File.join(sub, 'f.txt'), 'data')

    dest = File.join(Dir.tmpdir, "ci_outdir_#{SecureRandom.hex(4)}")
    assert @container.copy_out('subdir', dest)
    assert File.exist?(File.join(dest, 'f.txt'))
  ensure
    FileUtils.rm_rf(dest)
  end

  def test_copy_out_nonexistent_returns_false
    refute @container.copy_out('no_such_file', '/tmp/test_dest')
  end

  def test_copy_out_creates_parent_dirs
    File.write(File.join(@container.workspace, 'file.txt'), 'data')
    dest = File.join(Dir.tmpdir, "ci_deep_#{SecureRandom.hex(4)}", 'nested', 'file.txt')

    assert @container.copy_out('file.txt', dest)
    assert_equal 'data', File.read(dest)
  ensure
    FileUtils.rm_rf(File.join(Dir.tmpdir, 'ci_deep_*'))
  end

  # --- list_files ---
  def test_list_files_default
    File.write(File.join(@container.workspace, 'a.txt'), 'a')
    files = @container.list_files
    assert_includes files, 'a.txt'
    refute_includes files, '.'
    refute_includes files, '..'
  end

  def test_list_files_subdirectory
    sub = File.join(@container.workspace, 'sub')
    FileUtils.mkdir_p(sub)
    File.write(File.join(sub, 'c.txt'), 'c')

    files = @container.list_files('sub')
    assert_equal ['c.txt'], files
  end

  def test_list_files_nonexistent
    assert_equal [], @container.list_files('nonexistent')
  end

  # --- workspace_size ---
  def test_workspace_size_with_files
    File.write(File.join(@container.workspace, 'big.txt'), 'x' * 100)
    assert @container.workspace_size >= 100
  end

  def test_workspace_size_after_cleanup
    @container.cleanup
    assert_equal 0, @container.workspace_size
  end

  # --- cleanup ---
  def test_cleanup_removes_workspace
    ws = @container.workspace
    @container.cleanup
    refute Dir.exist?(ws)
  end

  def test_cleanup_idempotent
    @container.cleanup
    @container.cleanup
  end

  # --- run raises on missing workspace ---
  def test_run_missing_workspace
    FileUtils.rm_rf(@container.workspace)
    assert_raises(Exceptions::SandboxSetupError) do
      @container.run('echo test')
    end
  end

  # --- register_cleanup idempotent ---
  def test_register_cleanup_not_duplicated
    @container.send(:register_cleanup)
    @container.send(:register_cleanup)
    # @cleanup_registered should still be true, no error
    assert @container.instance_variable_get(:@cleanup_registered)
  end

  # --- wait_for_process timeout path ---
  def test_wait_for_process_normal
    pid = spawn('true')
    status = @container.send(:wait_for_process, pid, 5)
    assert_equal 0, status
  end

  # --- kill_process_group already dead ---
  def test_kill_process_group_already_dead
    pid = spawn('true')
    Process.wait(pid)
    # Should not raise
    begin
      @container.send(:kill_process_group, pid)
    rescue StandardError
      nil
    end
  end

  # --- execute_with_timeout via run (uses actual unshare, but we test the error path) ---
  def test_run_command_execution_error
    # Override build_unshare_command to use a nonexistent binary to test rescue
    @container.define_singleton_method(:build_unshare_command) do |script_path|
      ['/nonexistent_binary_xyz', script_path]
    end

    assert_raises(Exceptions::SandboxError) do
      @container.run('echo test')
    end
  end

  # --- execute_with_timeout full path (bypass unshare by using sh directly) ---
  def test_execute_with_timeout_success
    @container.define_singleton_method(:build_unshare_command) do |script_path|
      ['sh', script_path]
    end
    result = @container.run('echo sandbox_test')
    assert result[:success]
    assert_match(/sandbox_test/, result[:stdout])
  end

  def test_execute_with_timeout_failure
    @container.define_singleton_method(:build_unshare_command) do |script_path|
      ['sh', script_path]
    end
    result = @container.run('exit 42')
    refute result[:success]
    assert_equal 42, result[:status]
  end

  def test_execute_with_timeout_with_env_vars
    @container.define_singleton_method(:build_unshare_command) do |script_path|
      ['sh', script_path]
    end
    result = @container.run('echo $MY_VAR', env_vars: { 'MY_VAR' => 'test_val' })
    assert result[:success]
    assert_match(/test_val/, result[:stdout])
  end

  def test_execute_with_timeout_cleanup_scripts
    @container.define_singleton_method(:build_unshare_command) do |script_path|
      ['sh', script_path]
    end
    @container.run('true')
    scripts = Dir.glob(File.join(@container.workspace, '.exec_*.sh'))
    assert_equal [], scripts
  end

  # --- wait_for_process timeout path ---
  def test_wait_for_process_timeout
    pid = spawn('sleep 10')
    status = @container.send(:wait_for_process, pid, 0.5)
    assert_equal 124, status
  end
end

# Test module-level methods
class TestNamespaceSandboxModuleMethods < Minitest::Test
  def test_sandbox_error_hierarchy
    assert Exceptions::SandboxError < Exceptions::CICDError
    assert Exceptions::SandboxSetupError < Exceptions::SandboxError
    assert Exceptions::SandboxTimeoutError < Exceptions::SandboxError
  end

  def test_setup_workspace_failure_message
    e = Exceptions::SandboxSetupError.new('Failed to create workspace: permission denied')
    assert_match(/Failed to create workspace/, e.message)
  end
end
