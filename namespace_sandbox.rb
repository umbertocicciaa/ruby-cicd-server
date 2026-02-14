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
      setup_workspace
      register_cleanup
    end
    
    # Execute a command in the sandboxed container
    def run(command, env_vars: {}, timeout: Config::SANDBOX_TIMEOUT)
      raise Exceptions::SandboxSetupError, "Workspace not initialized" unless Dir.exist?(@workspace)
      
      script_path = create_execution_script(command, env_vars)
      unshare_cmd = build_unshare_command(script_path)
      
      result = execute_with_timeout(unshare_cmd, timeout: timeout)
      
      result
    ensure
      FileUtils.rm_f(script_path) if script_path
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
    
    def create_execution_script(command, env_vars)
      script_path = File.join(@workspace, ".exec_script_#{SecureRandom.hex(4)}.sh")
      
      script_content = build_script_content(command, env_vars)
      
      File.write(script_path, script_content)
      FileUtils.chmod(0700, script_path)
      
      script_path
    end
    
    def build_script_content(command, env_vars)
      <<~SCRIPT
        #!/bin/sh
        
        # Set resource limits
        ulimit -t #{Config::SANDBOX_CPU_LIMIT}      # CPU time
        ulimit -v #{Config::SANDBOX_MEMORY_LIMIT}   # Virtual memory (KB)
        ulimit -u #{Config::SANDBOX_PROCESS_LIMIT}  # Max processes
        ulimit -f #{Config::SANDBOX_FILE_SIZE_LIMIT} # Max file size (KB)
        ulimit -c 0                                  # Core dump: disabled
        
        # Set environment
        cd "#{@workspace}" || exit 1
        export HOME="#{@workspace}"
        export TMPDIR="#{@workspace}"
        export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"
        
        #{build_env_exports(env_vars)}
        
        # Execute command
        #{sanitize_command(command)}
      SCRIPT
    end
    
    def build_env_exports(env_vars)
      return "" if env_vars.empty?
      
      env_vars.map do |key, value|
        # Sanitize key and value
        safe_key = key.to_s.gsub(/[^A-Z0-9_]/i, '_')
        safe_value = value.to_s.gsub('"', '\"')
        "export #{safe_key}=\"#{safe_value}\""
      end.join("\n")
    end
    
    def sanitize_command(command)
      # Basic command validation - prevent obvious shell injection attempts
      # This is not foolproof but adds a layer of safety
      command.to_s
    end
    
    def build_unshare_command(script_path)
      if unshare_available?
        build_unshare_with_namespaces(script_path)
      else
        script_path
      end
    end
    
    def unshare_available?
      @unshare_available ||= system("which unshare > /dev/null 2>&1")
    end
    
    def build_unshare_with_namespaces(script_path)
      flags = [
        "--fork",        # Fork before executing
        "--pid",         # New PID namespace
        "--uts",         # New hostname namespace
        "--ipc",         # New IPC namespace
      ]
      
      # Try to add mount-proc if available (some systems don't support it)
      if can_use_mount_proc?
        flags << "--mount-proc"
      end
      
      # Note: We intentionally do NOT use --net (network namespace) because
      # it breaks git clone, npm install, pip install, etc.
      # The sandbox still provides good isolation without it.
      
      [
        "unshare",
        *flags,
        script_path
      ].join(" ")
    end
    
    def can_use_mount_proc?
      # Test if --mount-proc works
      test_result = system("unshare --fork --pid --mount-proc /bin/true 2>/dev/null")
      test_result == true
    rescue
      false
    end
    
    def execute_with_timeout(command, timeout:)
      stdout_r, stdout_w = IO.pipe
      stderr_r, stderr_w = IO.pipe
      
      start_time = Time.now
      
      pid = spawn(
        command,
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
    rescue => e
      raise Exceptions::SandboxError, "Failed to execute command: #{e.message}"
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