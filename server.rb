# frozen_string_literal: true

require 'socket'
require 'json'
require_relative 'executor'
require_relative 'logging'
require_relative 'constants'
require_relative 'exceptions'

module CICDServer
  class HTTPRequest
    attr_reader :method, :path, :headers, :body
    
    def initialize(client)
      @method, @path = parse_request_line(client)
      @headers = parse_headers(client)
      @body = read_body(client)
    end
    
    def json_body
      return {} if @body.nil? || @body.empty?
      JSON.parse(@body)
    rescue JSON::ParserError => e
      Logging.warn("Failed to parse JSON body: #{e.message}")
      {}
    end
    
    private
    
    def parse_request_line(client)
      request_line = client.gets
      return [nil, nil] if request_line.nil?
      
      parts = request_line.strip.split(' ')
      [parts[0], parts[1]]
    end
    
    def parse_headers(client)
      headers = {}
      
      while (line = client.gets) && line !~ /^\s*$/
        key, value = line.split(": ", 2)
        headers[key.strip] = value.strip if key && value
      end
      
      headers
    end
    
    def read_body(client)
      content_length = @headers["Content-Length"].to_i
      
      if content_length > Config::MAX_REQUEST_SIZE
        raise Exceptions::RequestTooLargeError.new(content_length, Config::MAX_REQUEST_SIZE)
      end
      
      content_length > 0 ? client.read(content_length) : ""
    end
  end
  
  class HTTPResponse
    attr_accessor :status_code, :status_message, :headers, :body
    
    def initialize(status_code: 200, status_message: "OK", body: "", content_type: "text/plain")
      @status_code = status_code
      @status_message = status_message
      @body = body
      @headers = {
        "Content-Type" => content_type,
        "Content-Length" => body.bytesize.to_s,
        "Server" => "Ruby-CICD/1.0",
        "Connection" => "close"
      }
    end
    
    def to_s
      response = "HTTP/1.1 #{@status_code} #{@status_message}\r\n"
      @headers.each { |key, value| response += "#{key}: #{value}\r\n" }
      response += "\r\n"
      response += @body
      response
    end
  end
  
  class Server
    attr_reader :port, :host
    
    def initialize(host: Config::SERVER_HOST, port: Config::SERVER_PORT)
      @host = host
      @port = port
      @server = nil
      @running = false
    end
    
    def start
      @server = TCPServer.new(@host, @port)
      @running = true
      
      Logging.info("=" * 60)
      Logging.info("Ruby CI/CD Server starting...")
      Logging.info("Listening on http://#{@host}:#{@port}")
      Logging.info("=" * 60)
      
      # Handle shutdown signals gracefully
      setup_signal_handlers
      
      accept_connections
    rescue Errno::EADDRINUSE
      Logging.fatal("Port #{@port} is already in use")
      exit 1
    rescue => e
      Logging.fatal("Failed to start server: #{e.message}")
      Logging.debug(e.backtrace.join("\n"))
      exit 1
    ensure
      shutdown
    end
    
    def shutdown
      return unless @running
      
      Logging.info("Shutting down server...")
      @running = false
      @server&.close
      Logging.info("Server stopped")
    end
    
    private
    
    def setup_signal_handlers
      %w[INT TERM].each do |signal|
        Signal.trap(signal) do
          puts "\n" # New line after ^C
          Logging.info("Received #{signal} signal")
          shutdown
          exit 0
        end
      end
    end
    
    def accept_connections
      while @running
        begin
          client = @server.accept
          Thread.start(client) { |c| handle_client(c) }
        rescue => e
          Logging.error("Error accepting connection: #{e.message}")
        end
      end
    end
    
    def handle_client(client)
      request = HTTPRequest.new(client)
      
      log_request(request)
      
      response = process_request(request)
      client.print(response.to_s)
      
    rescue Exceptions::RequestTooLargeError => e
      response = HTTPResponse.new(
        status_code: 413,
        status_message: "Request Entity Too Large",
        body: e.message
      )
      client.print(response.to_s)
      Logging.warn("Request too large: #{e.message}")
      
    rescue => e
      Logging.error("Error handling request: #{e.class} - #{e.message}")
      Logging.debug(e.backtrace&.join("\n"))
      
      response = HTTPResponse.new(
        status_code: 500,
        status_message: "Internal Server Error",
        body: "Internal server error occurred"
      )
      client.print(response.to_s)
      
    ensure
      client.close rescue nil
    end
    
    def process_request(request)
      case request.path
      when "/"
        handle_pipeline_request(request)
      when "/health"
        handle_health_check
      when "/metrics"
        handle_metrics_request
      else
        HTTPResponse.new(
          status_code: 404,
          status_message: "Not Found",
          body: "Endpoint not found: #{request.path}"
        )
      end
    end
    
    def handle_pipeline_request(request)
      return method_not_allowed unless request.method == "POST"
      
      data = request.json_body
      repository = data["repository"]
      build = data["build"]
      deploy = data["deploy"]
      
      result = Executor.execution(repository, build, deploy)
      
      HTTPResponse.new(
        status_code: 200,
        status_message: "OK",
        body: result.to_s
      )
    end
    
    def handle_health_check
      HTTPResponse.new(
        status_code: 200,
        status_message: "OK",
        body: "OK",
        content_type: "text/plain"
      )
    end
    
    def handle_metrics_request
      metrics = Monitoring.get_metrics
      
      HTTPResponse.new(
        status_code: 200,
        status_message: "OK",
        body: JSON.pretty_generate(metrics.to_h),
        content_type: "application/json"
      )
    end
    
    def method_not_allowed
      HTTPResponse.new(
        status_code: 405,
        status_message: "Method Not Allowed",
        body: "Only POST requests are allowed for pipeline execution"
      )
    end
    
    def log_request(request)
      Logging.info("#{request.method} #{request.path} - Content-Length: #{request.headers['Content-Length'] || 0}")
      Logging.debug("Headers: #{request.headers.inspect}")
      Logging.debug("Body: #{request.body}") unless request.body.empty?
    end
  end
  
  def self.start
    server = Server.new
    server.start
  end
end

# Start the server if this file is run directly
if __FILE__ == $PROGRAM_NAME
  CICDServer.start
end
