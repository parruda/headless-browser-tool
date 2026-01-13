# frozen_string_literal: true

require "fileutils"

module HeadlessBrowserTool
  module DirectorySetup
    HBT_DIR = File.expand_path("~/.hbt")
    SCREENSHOTS_DIR = File.join(HBT_DIR, "screenshots").freeze
    SESSIONS_DIR = File.join(HBT_DIR, "sessions").freeze
    LOGS_DIR = File.join(HBT_DIR, "logs").freeze

    module_function

    def setup_directories(include_logs: false)
      # Create all necessary directories
      FileUtils.mkdir_p(SCREENSHOTS_DIR)
      FileUtils.mkdir_p(SESSIONS_DIR)
      FileUtils.mkdir_p(LOGS_DIR) if include_logs

      # Create .gitignore in .hbt directory
      gitignore_path = File.join(HBT_DIR, ".gitignore")
      File.write(gitignore_path, "*\n") unless File.exist?(gitignore_path)
    end
  end
end
