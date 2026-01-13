# frozen_string_literal: true

require_relative "logger"

module HeadlessBrowserTool
  class StrictSessionMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      # Log request headers if enabled
      log_request_headers(env) if HeadlessBrowserTool::Server.show_headers

      # Extract session ID from X-Session-ID header only
      session_id = env["HTTP_X_SESSION_ID"]

      # For MCP requests, auto-generate session ID if not provided
      if mcp_request?(env) && (session_id.nil? || session_id.empty?)
        # Auto-generate a session ID for clients that don't provide one
        session_id = "auto-#{SecureRandom.hex(8)}"
        env["HTTP_X_SESSION_ID"] = session_id
      end

      # Sanitize session ID
      if session_id
        session_id = sanitize_session_id(session_id)
        if session_id.nil?
          return [
            400,
            { "Content-Type" => "application/json" },
            [{ error: "Invalid X-Session-ID format" }.to_json]
          ]
        end
      end

      # Store in environment for downstream use
      env["hbt.session_id"] = session_id || "default"

      # Call the app
      status, headers, response = @app.call(env)

      # Add session ID to response headers
      headers["X-Session-ID"] = session_id if session_id

      [status, headers, response]
    end

    private

    def sanitize_session_id(value)
      return nil if value.nil? || value.empty?

      # Ensure it's alphanumeric with underscores/hyphens only
      sanitized = value.gsub(/[^a-zA-Z0-9_\-]/, "")

      # Limit length
      sanitized = sanitized[0..64]

      # Return nil if invalid
      return nil if sanitized.empty?

      sanitized
    end

    def mcp_request?(env)
      env["PATH_INFO"]&.start_with?("/mcp")
    end

    def oauth_discovery_request?(env)
      path = env["PATH_INFO"]
      return true if path&.start_with?("/.well-known/")
      return true if path == "/register"
      false
    end

    def log_request_headers(env)
      HeadlessBrowserTool::Logger.log.info "\n=== REQUEST HEADERS ==="
      HeadlessBrowserTool::Logger.log.info "Method: #{env["REQUEST_METHOD"]} #{env["PATH_INFO"]}"
      HeadlessBrowserTool::Logger.log.info "Remote IP: #{env["REMOTE_ADDR"]}"

      # Log all HTTP headers
      env.select { |k, _v| k.start_with?("HTTP_") }.each do |key, value|
        header_name = key.sub("HTTP_", "").split("_").map(&:capitalize).join("-")
        HeadlessBrowserTool::Logger.log.info "#{header_name}: #{value}"
      end

      # Log specific session-related info
      HeadlessBrowserTool::Logger.log.info "Session ID: #{env["HTTP_X_SESSION_ID"] || "NOT PROVIDED"}"
      HeadlessBrowserTool::Logger.log.info "=====================\n"
    end
  end
end
