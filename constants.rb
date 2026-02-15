# frozen_string_literal: true

module Config
  # Directory configuration
  REPOSITORY_DESTINATION = "repository_cloned"
  LOGS_DIRECTORY = "logs"
  LOGS_FILE = "cicd.log"
  
  # Sandbox configuration
  SANDBOX_TIMEOUT = 600                               # 10 minutes in seconds
  SANDBOX_CPU_LIMIT = 600                             # CPU time in seconds
  SANDBOX_MEMORY_LIMIT = 2 * 1024 * 1024              # 2GB in KB
  SANDBOX_PROCESS_LIMIT = 50
  SANDBOX_FILE_SIZE_LIMIT = 100 * 1024                # 100MB in KB
  
  # Server configuration
  SERVER_PORT = ENV.fetch('CICD_PORT', 8080).to_i
  SERVER_HOST = ENV.fetch('CICD_HOST', 'localhost')
  MAX_REQUEST_SIZE = 10 * 1024 * 1024                 # 10MB
  
  # Logging configuration
  LOG_ROTATION_COUNT = 5
  LOG_FILE_SIZE = 1_048_576                           # 1MB
  
  # Git configuration
  GIT_CLONE_DEPTH = ENV.fetch('GIT_CLONE_DEPTH', nil) # nil = full clone, or set to number
  GIT_TIMEOUT = 300                                   # 5 minutes
end
