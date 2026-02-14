require 'fileutils'
require 'securerandom'
require 'tmpdir'
require 'timeout'

module NamespaceSandbox
  class Container
    attr_reader :workspace, :container_id
    
    def initialize
      @container_id = SecureRandom.hex(8)
      @workspace = File.join(Dir.tmpdir, "container_#{@container_id}")
      setup_workspace
    end
    
    def run(command, env_vars: {})
      script_path = create_execution_script(command, env_vars)
      
      unshare_cmd = build_unshare_command(script_path)
      
      result = execute_with_timeout(unshare_cmd, timeout: 600)
      
      FileUtils.rm_f(script_path)
      result
    end
    
    def copy_into(source_path, dest_name = nil)
      dest_name ||= File.basename(source_path)
      dest_path = File.join(@workspace, dest_name)
      
      if File.directory?(source_path)
        FileUtils.cp_r(source_path, dest_path)
      else
        FileUtils.cp(source_path, dest_path)
      end
      
      dest_path
    end
    
    def copy_out(source_name, dest_path)
      source_path = File.join(@workspace, source_name)
      
      if File.exist?(source_path)
        if File.directory?(source_path)
          FileUtils.cp_r(source_path, dest_path)
        else
          FileUtils.cp(source_path, dest_path)
        end
        true
      else
        false
      end
    end
    
    def cleanup
      FileUtils.rm_rf(@workspace) if Dir.exist?(@workspace)
    end
    
    private
    
    def setup_workspace
      FileUtils.mkdir_p(@workspace)
      FileUtils.chmod(0700, @workspace)
    end
    
    def create_execution_script(command, env_vars)
      script_path = File.join(@workspace, ".exec_script_#{SecureRandom.hex(4)}.sh")
      
      script_content = <<~SCRIPT
        #!/bin/sh
        
        # Set resource limits
        ulimit -t 600      # CPU time: 10 minutes
        ulimit -v 2097152  # Virtual memory: 2GB (in KB)
        ulimit -u 50       # Max processes
        ulimit -f 102400   # Max file size: 100MB (in KB)
        ulimit -c 0        # Core dump: disabled
        
        # Set environment
        cd "#{@workspace}" || exit 1
        export HOME="#{@workspace}"
        export TMPDIR="#{@workspace}"
        export PATH="/usr/local/bin:/usr/bin:/bin"
        
      SCRIPT
      
      env_vars.each do |key, value|
        script_content += "export #{key}=\"#{value}\"\n"
      end
      
      script_content += "\n# Execute command\n"
      script_content += "#{command}\n"
      
      File.write(script_path, script_content)
      FileUtils.chmod(0700, script_path)
      
      script_path
    end
    
    def build_unshare_command(script_path)
      unshare_available = system("which unshare > /dev/null 2>&1")
      
      if unshare_available
        [
          "unshare",
          "--fork",           # Fork before executing
          "--pid",            # New PID namespace
          "--mount-proc",     # Mount new /proc
          "--uts",            # New hostname namespace
          "--ipc",            # New IPC namespace
          script_path
        ].join(" ")
      else
        script_path
      end
    end
    
    def execute_with_timeout(command, timeout:)
      stdout_r, stdout_w = IO.pipe
      stderr_r, stderr_w = IO.pipe
      
      pid = spawn(
        command,
        out: stdout_w,
        err: stderr_w,
        chdir: @workspace,
        pgroup: true
      )
      
      stdout_w.close
      stderr_w.close
      
      stdout_thread = Thread.new { stdout_r.read }
      stderr_thread = Thread.new { stderr_r.read }
      
      begin
        Timeout.timeout(timeout) do
          Process.wait(pid)
        end
        
        exit_status = $?.exitstatus
      rescue Timeout::Error
        begin
          Process.kill('TERM', -pid)
          sleep 1
          Process.kill('KILL', -pid) rescue nil
        rescue Errno::ESRCH
        end
        
        begin
          Process.wait(pid)
        rescue Errno::ECHILD
        end
        
        exit_status = 124
      end
      
      stdout_data = stdout_thread.value
      stderr_data = stderr_thread.value
      
      stdout_r.close
      stderr_r.close
      
      {
        output: stdout_data + stderr_data,
        stdout: stdout_data,
        stderr: stderr_data,
        status: exit_status,
        success: exit_status == 0
      }
    end
  end
  
  def self.run(command, env_vars: {})
    container = Container.new
    begin
      container.run(command, env_vars: env_vars)
    ensure
      container.cleanup
    end
  end
  
  def self.with_container
    container = Container.new
    begin
      yield container
    ensure
      container.cleanup
    end
  end
end