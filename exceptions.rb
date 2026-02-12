module Exceptions
  class EmptyUrlException < StandardError
    def initialize(msg = "Repository URL is required but was not provided or is empty. Please supply a valid git repository URL as the first argument (e.g., 'https://github.com/user/repo.git').")
      super(msg)
    end
  end
  
  class PullFailException < StandardError
    def initialize(msg = "Failed to clone the git repository. Verify that the URL is correct, the repository exists, and you have the necessary access permissions.")
      super(msg)
    end
  end
  
  class BuildException < StandardError
    def initialize(msg = "Build command failed with a non-zero exit status. Check the build output above for errors and ensure all dependencies are installed.")
      super(msg)
    end
  end

  class EmptyBuildCommandException < StandardError
    def initialize(msg = "Build command is required but was not provided or is empty. Please supply a valid build command as the second argument (e.g., 'python setup.py build').")
      super(msg)
    end
  end

  class EmptyDeployCommandException < StandardError
    def initialize(msg = "Deploy command is required but was not provided or is empty. Please supply a valid build command as the second argument (e.g., 'python setup.py build').")
      super(msg)
    end
  end

  class DeployException < StandardError
    def initialize(msg = "Build command failed with a non-zero exit status. Check the build output above for errors and ensure all dependencies are installed.")
      super(msg)
    end
  end
end
