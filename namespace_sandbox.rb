# frozen_string_literal: true

require 'fileutils'
require 'securerandom'
require 'tmpdir'
require 'timeout'
require 'find'
require_relative 'constants'
require_relative 'exceptions'

module NamespaceSandbox
  class Container
    attr_reader :workspace, :container_id

    def initialize
      @container_id = SecureRandom.hex(8)
      @workspace = File.join(Dir.tmpdir, "container_#{@container_id}")
      @cleanup_registered = false
      require_unshare!
      setup_workspace
      register_cleanup
    end

    # Execute a command in the sandboxed container
    def run(command, env_vars: {}, timeout: Config::SANDBOX_TIMEOUT)
      raise Exceptions::SandboxSetupError, "Workspace not initialized" unless Dir.exist?(@workspace)

      execute_with_timeout(command, env_vars, timeout: timeout)
    end

    # Copy file or directory into the container
    def copy_into(source_path, dest_name = nil)
      raise ArgumentError, "Source path does not exist: #{source_path}" unless File.exist?(source_path)

      dest_name ||= File.basename(source_path)
      dest_path = File.join(@workspace, dest_name)

      if File.directory?(source_path)
        FileUtils.cp_r(source_path, dest_path)
      else
        FileUtils.cp(source_path, dest_path, preserve: true)
      end

      dest_path
    end

    # Copy file or directory out of the container
    def copy_out(source_name, dest_path)
      source_path = File.join(@workspace, source_name)
      return false unless File.exist?(source_path)

      FileUtils.mkdir_p(File.dirname(dest_path))

      if File.directory?(source_path)
        FileUtils.cp_r(source_path, dest_path)
      else
        FileUtils.cp(source_path, dest_path, preserve: true)
      end

      true
    end

    # List files in the container workspace
    def list_files(path = ".")
      full_path = File.join(@workspace, path)
      return [] unless Dir.exist?(full_path)

      Dir.entries(full_path).reject { |f| f == '.' || f == '..' }
    end

    # Get the size of the workspace
    def workspace_size
      return 0 unless Dir.exist?(@workspace)

      total_size = 0
      Find.find(@workspace) do |path|
        total_size += File.size(path) if File.file?(path)
      end
      total_size
    rescue
      0
    end

    # Clean up the container workspace
    def cleanup
      return unless Dir.exist?(@workspace)

      FileUtils.rm_rf(@workspace)
    rescue => e
      warn "Warning: Failed to clean up workspace #{@workspace}: #{e.message}"
    end

    private

    def require_unshare!
      unless system("which unshare > /dev/null 2>&1")
        raise Exceptions::SandboxSetupError,
          "unshare is required but not found. This software requires Linux with util-linux installed."
      end

      unless system("unshare --fork --pid --mount-proc /bin/true 2>/dev/null")
        raise Exceptions::SandboxSetupError,
          "unshare is available but lacks required privileges. Run as root or enable user namespaces " \
          "(sysctl kernel.unprivileged_userns_clone=1)."
      end
    end

    def setup_workspace
      FileUtils.mkdir_p(@workspace)
      FileUtils.chmod(0700, @workspace)
    rescue => e
      raise Exceptions::SandboxSetupError, "Failed to create workspace: #{e.message}"
    end

    def register_cleanup
      return if @cleanup_registered

      at_exit { cleanup }
      @cleanup_registered = true
    end

    def execute_with_timeout(command, env_vars, timeout:)
      stdout_r, stdout_w = IO.pipe
      stderr_r, stderr_w = IO.pipe

      start_time = Time.now

      begin
        env = build_clean_environment(env_vars)
        script_path = create_execution_script(command)
        actual_command = build_unshare_command(script_path)

        pid = spawn(
          env,
          *actual_command,
          out: stdout_w,
          err: stderr_w,
          chdir: @workspace,
          pgroup: true,
          close_others: true
        )

        stdout_w.close
        stderr_w.close

        stdout_thread = Thread.new { safe_read(stdout_r) }
        stderr_thread = Thread.new { safe_read(stderr_r) }

        exit_status = wait_for_process(pid, timeout)

        stdout_data = stdout_thread.value
        stderr_data = stderr_thread.value

        stdout_r.close
        stderr_r.close

        execution_time = Time.now - start_time

        build_result(stdout_data, stderr_data, exit_status, execution_time)
      ensure
        Dir.glob(File.join(@workspace, ".exec_*.sh")).each do |f|
          FileUtils.rm_f(f) rescue nil
        end
      end
    rescue Exceptions::SandboxError
      raise
    rescue => e
      raise Exceptions::SandboxError, "Failed to execute command: #{e.message}"
    end

    def build_clean_environment(custom_vars)
      env = {
        'HOME' => @workspace,
        'TMPDIR' => @workspace,
        'PATH' => '/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin',
        'LANG' => ENV['LANG'] || 'en_US.UTF-8',
        'LC_ALL' => ENV['LC_ALL'] || 'en_US.UTF-8'
      }

      custom_vars.each do |key, value|
        safe_key = key.to_s.gsub(/[^A-Z0-9_]/i, '_')
        env[safe_key] = value.to_s
      end

      env
    end

    def build_unshare_command(script_path)
      [
        "unshare",
        "--fork",          # fork before exec so PID namespace works
        "--pid",           # new PID namespace — process sees only itself
        "--mount-proc",    # mount fresh /proc inside so ps/kill work correctly
        "--uts",           # new UTS namespace — isolated hostname
        "--ipc",           # new IPC namespace — isolated shared memory / semaphores
        "sh", script_path
      ]
    end

    def create_execution_script(command)
      script_path = File.join(@workspace, ".exec_#{SecureRandom.hex(4)}.sh")

      script_content = <<~SCRIPT
        #!/bin/sh
        set -e

        # Resource limits
        ulimit -t #{Config::SANDBOX_CPU_LIMIT}  2>/dev/null || true
        ulimit -v #{Config::SANDBOX_MEMORY_LIMIT} 2>/dev/null || true
        ulimit -f #{Config::SANDBOX_FILE_SIZE_LIMIT} 2>/dev/null || true
        ulimit -u #{Config::SANDBOX_PROCESS_LIMIT} 2>/dev/null || true
        ulimit -c 0 2>/dev/null || true

        # Execute command
        #{command}
      SCRIPT

      File.write(script_path, script_content)
      FileUtils.chmod(0700, script_path)

      script_path
    end

    def safe_read(io)
      io.read
    rescue => e
      "Error reading output: #{e.message}"
    end

    def wait_for_process(pid, timeout)
      Timeout.timeout(timeout) do
        Process.wait(pid)
        return $?.exitstatus
      end
    rescue Timeout::Error
      kill_process_group(pid)
      124
    end

    def kill_process_group(pid)
      Process.kill('TERM', -pid)
      sleep 1
      Process.kill('KILL', -pid) rescue nil
    rescue Errno::ESRCH
      # already dead
    ensure
      Process.wait(pid) rescue nil
    end

    def build_result(stdout_data, stderr_data, exit_status, execution_time)
      {
        output: stdout_data + stderr_data,
        stdout: stdout_data,
        stderr: stderr_data,
        status: exit_status,
        success: exit_status == 0,
        execution_time: execution_time.round(2),
        timed_out: exit_status == 124
      }
    end
  end

  # Execute a command in a temporary container that is cleaned up automatically
  def self.run(command, env_vars: {}, timeout: Config::SANDBOX_TIMEOUT)
    container = Container.new
    begin
      container.run(command, env_vars: env_vars, timeout: timeout)
    ensure
      container.cleanup
    end
  end

  # Yield a container to a block and clean it up automatically
  def self.with_container
    container = Container.new
    begin
      yield container
    ensure
      container.cleanup
    end
  end
end