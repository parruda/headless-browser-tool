# frozen_string_literal: true

require "sinatra/base"
require "rack"
require "fileutils"
require "securerandom"
require "json"
require_relative "browser"
require_relative "tools"
require_relative "session_manager"
require_relative "session_middleware"
require_relative "strict_session_middleware"
require_relative "browser_adapter"
require_relative "logger"
require_relative "session_persistence"
require_relative "directory_setup"

module HeadlessBrowserTool
  class Server < Sinatra::Base
    class << self
      attr_accessor :browser_instance, :session_manager, :single_session_mode, :show_headers, :session_id

      def start_server(options = {})
        # Initialize logger for HTTP mode
        HeadlessBrowserTool::Logger.initialize_logger(mode: :http)

        # Check if we should use single session mode
        @single_session_mode = options[:single_session] || ENV["HBT_SINGLE_SESSION"] == "true"
        @show_headers = options[:show_headers] || ENV["HBT_SHOW_HEADERS"] == "true"

        # Validate session_id option
        if options[:session_id] && !@single_session_mode
          puts "Error: --session-id can only be used with --single-session"
          exit 1
        end

        if @single_session_mode
          puts "Running in single session mode"
          if options[:session_id]
            puts "Session ID: #{options[:session_id]}"
            @session_id = options[:session_id]
          end
          @browser_instance = Browser.new(headless: options[:headless])

          # Restore session if session_id provided
          restore_single_session if @session_id
        else
          puts "Running in multi-session mode"
          @session_manager = SessionManager.new(headless: options[:headless])
        end

        # Setup directory structure
        DirectorySetup.setup_directories

        puts "Starting HeadlessBrowserTool MCP server on port #{options[:port]}"

        # Register shutdown hook for single session persistence
        at_exit { save_single_session } if @single_session_mode && @session_id

        # Configure and run with Puma directly
        require "puma"
        require "puma/configuration"
        require "puma/launcher"

        puma_config = Puma::Configuration.new do |config|
          config.bind "tcp://0.0.0.0:#{options[:port]}"
          config.environment "production"
          config.quiet false
          config.app Server
        end

        launcher = Puma::Launcher.new(puma_config)
        launcher.run
      end

      private

      def restore_single_session
        SessionPersistence.restore_session(@session_id, @browser_instance.session)
      end

      def save_single_session
        return unless @session_id && @browser_instance

        SessionPersistence.save_session(@session_id, @browser_instance.session)
      end
    end

    # Use session middleware that allows /mcp without session for Claude Code
    use SessionMiddleware

    # Session management endpoints
    get "/sessions" do
      if Server.single_session_mode
        { mode: "single", message: "Server is running in single session mode" }.to_json
      else
        content_type :json
        Server.session_manager.session_info.to_json
      end
    end

    delete "/sessions/:id" do
      if Server.single_session_mode
        status 400
        { error: "Cannot manage sessions in single session mode" }.to_json
      else
        Server.session_manager.close_session(params[:id])
        { message: "Session closed", session_id: params[:id] }.to_json
      end
    end

    # MCP endpoint for Claude Code
    post "/mcp" do
      content_type :json
      
      begin
        request.body.rewind
        body = request.body.read
        request_data = JSON.parse(body)
        
        case request_data["method"]
        when "initialize"
          {
            jsonrpc: "2.0",
            id: request_data["id"],
            result: {
              protocolVersion: "2025-06-18",
              capabilities: {
                tools: { listChanged: true }
              },
              serverInfo: {
                name: "headless-browser",
                version: HeadlessBrowserTool::VERSION
              }
            }
          }.to_json
          
        when "tools/list"
          tools = HeadlessBrowserTool::Tools::ALL_TOOLS.map do |tool_class|
            {
              name: "mcp__headless_browser__#{tool_class.tool_name}",
              description: tool_class.description,
              inputSchema: tool_class.input_schema_to_json || { type: 'object', properties: {}, required: [] }
            }
          end
          
          {
            jsonrpc: "2.0",
            id: request_data["id"],
            result: { tools: tools }
          }.to_json
          
        when "notifications/initialized"
          { jsonrpc: "2.0", result: nil }.to_json
          
        when "tools/call"
          tool_name = request_data.dig("params", "name")
          tool_args = request_data.dig("params", "arguments") || {}
          
          # Remove prefix
          actual_tool_name = tool_name.sub(/^mcp__headless_browser__/, "")
          
          tool_class = HeadlessBrowserTool::Tools::ALL_TOOLS.find do |tc|
            tc.tool_name == actual_tool_name
          end
          
          if tool_class
            session_id = env["hbt.session_id"]
            Thread.current[:hbt_session_id] = session_id
            
            begin
              tool = tool_class.new
              result = tool.execute(**tool_args.transform_keys(&:to_sym))
              
              {
                jsonrpc: "2.0",
                id: request_data["id"],
                result: {
                  content: [{ type: "text", text: result.to_json }]
                }
              }.to_json
            ensure
              Thread.current[:hbt_session_id] = nil
            end
          else
            {
              jsonrpc: "2.0",
              id: request_data["id"],
              error: {
                code: -32601,
                message: "Tool not found: #{tool_name}"
              }
            }.to_json
          end
          
        else
          {
            jsonrpc: "2.0",
            id: request_data["id"],
            error: {
              code: -32601,
              message: "Method not found: #{request_data["method"]}"
            }
          }.to_json
        end
      rescue => e
        {
          jsonrpc: "2.0",
          id: request_data["id"],
          error: {
            code: -32603,
            message: "Internal error: #{e.message}"
          }
        }.to_json
      end
    end

    # Default route
    get "/" do
      mode = Server.single_session_mode ? "single session" : "multi-session"
      "HeadlessBrowserTool MCP Server is running in #{mode} mode"
    end
  end
end
