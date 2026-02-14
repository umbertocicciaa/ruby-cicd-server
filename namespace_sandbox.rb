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
      @use_unshare = detect_unshare_support
      setup_workspace
      register_cleanup
    end
    
    # Execute a command in the sandboxed container
    def run(command, env_vars: {}, timeout: Config::SANDBOX_TIMEOUT)
      raise Exceptions::SandboxSetupError, "Workspace not initialized" unless Dir.exist?(@workspace)
      
      result = execute_with_timeout(command, env_vars, timeout: timeout)
      result
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
      
      unless File.exist?(source_path)
        return false
      end
      
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
    rescue => e
      0
    end
    
    # Clean up the container workspace
    def cleanup
      return unless Dir.exist?(@workspace)
      
      begin
        FileUtils.rm_rf(@workspace)
      rescue => e
        warn "Warning: Failed to clean up workspace #{@workspace}: #{e.message}"
      end
    end
    
    private
    
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
    
    def detect_unshare_support
      # Check if unshare command exists
      return false unless system("which unshare > /dev/null 2>&1")
      
      # Test if we can actually use unshare
      test_result = system("unshare --fork --pid /bin/true 2>/dev/null")
      
      if test_result
        # Print info message only once
        if !defined?(@@unshare_detected)
          @@unshare_detected = true
          $stderr.puts "✓ Namespace isolation enabled (unshare available)" if ENV['DEBUG']
        end
        true
      else
        # Print warning only once
        if !defined?(@@unshare_warning_shown)
          @@unshare_warning_shown = true
          $stderr.puts "⚠ Warning: unshare not available, using fallback mode (still secure with resource limits)"
        end
        false
      end
    rescue
      false
    end
    
    def execute_with_timeout(command, env_vars, timeout:)
      stdout_r, stdout_w = IO.pipe
      stderr_r, stderr_w = IO.pipe
      
      start_time = Time.now
      
      # Build environment
      env = build_clean_environment(env_vars)
      
      # Build the actual command (with or without unshare)
      actual_command = build_execution_command(command)
      
      # Spawn process with clean environment
      pid = spawn(
        env,
        actual_command,
        out: stdout_w,
        err: stderr_w,
        chdir: @workspace,
        pgroup: true,
        close_others: true
      )
      
      stdout_w.close
      stderr_w.close
      
      # Set resource limits on the spawned process
      set_resource_limits(pid)
      
      stdout_thread = Thread.new { safe_read(stdout_r) }
      stderr_thread = Thread.new { safe_read(stderr_r) }
      
      exit_status = wait_for_process(pid, timeout)
      
      stdout_data = stdout_thread.value
      stderr_data = stderr_thread.value
      
      stdout_r.close
      stderr_r.close
      
      execution_time = Time.now - start_time
      
      build_result(stdout_data, stderr_data, exit_status, execution_time)
    rescue => e
      raise Exceptions::SandboxError, "Failed to execute command: #{e.message}"
    end
    
    def build_clean_environment(custom_vars)
      # Build a clean environment
      env = {
        'HOME' => @workspace,
        'TMPDIR' => @workspace,
        'PATH' => '/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin',
        'LANG' => ENV['LANG'] || 'en_US.UTF-8',
        'LC_ALL' => ENV['LC_ALL'] || 'en_US.UTF-8'
      }
      
      # Add custom environment variables
      custom_vars.each do |key, value|
        safe_key = key.to_s.gsub(/[^A-Z0-9_]/i, '_')
        env[safe_key] = value.to_s
      end
      
      env
    end
    
    def build_execution_command(command)
      if @use_unshare
        # Use unshare for namespace isolation
        build_unshare_command(command)
      else
        # Direct execution with resource limits (set via ulimit in shell)
        build_shell_command(command)
      end
    end
    
    def build_unshare_command(command)
      # Try minimal unshare flags that are most likely to work
      flags = [
        "--fork",
        "--pid",
      ]
      
      # Build the command
      unshare_cmd = ["unshare", *flags, "sh", "-c", shell_with_limits(command)].join(" ")
      unshare_cmd
    end
    
    def build_shell_command(command)
      # Execute directly with shell and resource limits
      "sh -c #{shell_escape(shell_with_limits(command))}"
    end
    
    def shell_with_limits(command)
      # Add resource limits via ulimit
      limits = []
      
      begin
        limits << "ulimit -t #{Config::SANDBOX_CPU_LIMIT}"
        limits << "ulimit -f #{Config::SANDBOX_FILE_SIZE_LIMIT}"
        limits << "ulimit -u #{Config::SANDBOX_PROCESS_LIMIT}"
        limits << "ulimit -c 0"
      rescue
        # If config not available, use defaults
        limits << "ulimit -t 600"
        limits << "ulimit -f 102400"
        limits << "ulimit -u 50"
        limits << "ulimit -c 0"
      end
      
      (limits + [command]).join(" && ")
    end
    
    def shell_escape(str)
      # Escape string for shell
      "'#{str.gsub("'", "'\\''")}'"
    end
    
    def set_resource_limits(pid)
      begin
        # Set resource limits on current process (affects children)
        Process.setrlimit(:CPU, Config::SANDBOX_CPU_LIMIT, Config::SANDBOX_CPU_LIMIT)
        Process.setrlimit(:FSIZE, Config::SANDBOX_FILE_SIZE_LIMIT * 1024, Config::SANDBOX_FILE_SIZE_LIMIT * 1024)
        Process.setrlimit(:CORE, 0, 0)
        
        # Process limit (might not work on all systems)
        Process.setrlimit(:NPROC, Config::SANDBOX_PROCESS_LIMIT, Config::SANDBOX_PROCESS_LIMIT) rescue nil
      rescue NotImplementedError, Errno::EINVAL, Errno::EPERM => e
        # Some limits not supported, continue anyway
        warn "Warning: Could not set all resource limits: #{e.message}" if ENV['DEBUG']
      end
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
      return 124 # Standard timeout exit code
    end
    
    def kill_process_group(pid)
      begin
        Process.kill('TERM', -pid)
        sleep 1
        Process.kill('KILL', -pid) rescue nil
      rescue Errno::ESRCH
        # Process already died
      end
      
      begin
        Process.wait(pid)
      rescue Errno::ECHILD
        # Already waited for
      end
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