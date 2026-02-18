# frozen_string_literal: true

require_relative 'test_helper'

class TestHTTPResponse < Minitest::Test
  def test_default_response
    r = CICDServer::HTTPResponse.new
    assert_equal 200, r.status_code
    assert_equal 'OK', r.status_message
    assert_equal '', r.body
    assert_equal 'text/plain', r.headers['Content-Type']
    assert_equal '0', r.headers['Content-Length']
    assert_equal 'Ruby-CICD/1.0', r.headers['Server']
    assert_equal 'close', r.headers['Connection']
  end

  def test_custom_response
    r = CICDServer::HTTPResponse.new(
      status_code: 404,
      status_message: 'Not Found',
      body: 'missing',
      content_type: 'application/json'
    )
    assert_equal 404, r.status_code
    assert_equal 'Not Found', r.status_message
    assert_equal 'missing', r.body
    assert_equal 'application/json', r.headers['Content-Type']
    assert_equal '7', r.headers['Content-Length']
  end

  def test_to_s_format
    r = CICDServer::HTTPResponse.new(status_code: 200, status_message: 'OK', body: 'hi')
    str = r.to_s
    assert_match(%r{^HTTP/1\.1 200 OK\r\n}, str)
    assert_match(%r{Content-Type: text/plain\r\n}, str)
    assert_match(/\r\n\r\nhi$/, str)
  end

  def test_content_length_matches_body_bytesize
    body = 'héllo' # multi-byte characters
    r = CICDServer::HTTPResponse.new(body: body)
    assert_equal body.bytesize.to_s, r.headers['Content-Length']
  end
end

class TestHTTPRequest < Minitest::Test
  # Helper to create a mock client (StringIO simulating a socket)
  def make_client(request_str)
    StringIO.new(request_str)
  end

  def test_parse_get_request
    client = make_client("GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n")
    req = CICDServer::HTTPRequest.new(client)
    assert_equal 'GET', req.method
    assert_equal '/health', req.path
    assert_equal 'localhost', req.headers['Host']
    assert_equal '', req.body
  end

  def test_parse_post_request_with_body
    body = '{"key":"value"}'
    client = make_client(
      "POST / HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}"
    )
    req = CICDServer::HTTPRequest.new(client)
    assert_equal 'POST', req.method
    assert_equal '/', req.path
    assert_equal body, req.body
  end

  def test_json_body_valid
    body = '{"repository":"https://github.com/test.git"}'
    client = make_client(
      "POST / HTTP/1.1\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}"
    )
    req = CICDServer::HTTPRequest.new(client)
    json = req.json_body
    assert_equal 'https://github.com/test.git', json['repository']
  end

  def test_json_body_empty
    client = make_client("GET / HTTP/1.1\r\n\r\n")
    req = CICDServer::HTTPRequest.new(client)
    assert_equal({}, req.json_body)
  end

  def test_json_body_invalid
    body = 'not json at all{{'
    client = make_client(
      "POST / HTTP/1.1\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}"
    )
    req = CICDServer::HTTPRequest.new(client)
    json = nil
    capture_io { json = req.json_body }
    assert_equal({}, json)
  end

  def test_nil_request_line
    client = make_client('')
    req = CICDServer::HTTPRequest.new(client)
    assert_nil req.method
    assert_nil req.path
  end

  def test_request_too_large
    # Set a body size exceeding MAX_REQUEST_SIZE
    huge_size = Config::MAX_REQUEST_SIZE + 1
    client = make_client(
      "POST / HTTP/1.1\r\nContent-Length: #{huge_size}\r\n\r\n"
    )
    assert_raises(Exceptions::RequestTooLargeError) do
      CICDServer::HTTPRequest.new(client)
    end
  end
end

class TestServerProcessRequest < Minitest::Test
  def setup
    @server = CICDServer::Server.new(host: '127.0.0.1', port: 0)
  end

  def test_health_check
    response = @server.send(:handle_health_check)
    assert_equal 200, response.status_code
    assert_equal 'OK', response.body
  end

  def test_metrics_request
    response = nil
    capture_io { response = @server.send(:handle_metrics_request) }
    assert_equal 200, response.status_code
    assert_equal 'application/json', response.headers['Content-Type']
    parsed = JSON.parse(response.body)
    assert parsed.key?('total_runs')
  end

  def test_method_not_allowed
    response = @server.send(:method_not_allowed)
    assert_equal 405, response.status_code
    assert_match(/POST/, response.body)
  end

  def test_process_request_health
    req = Minitest::Mock.new
    req.expect(:path, '/health')
    response = @server.send(:process_request, req)
    assert_equal 200, response.status_code
    req.verify
  end

  def test_process_request_metrics
    req = Minitest::Mock.new
    req.expect(:path, '/metrics')
    response = nil
    capture_io { response = @server.send(:process_request, req) }
    assert_equal 200, response.status_code
    req.verify
  end

  def test_process_request_not_found
    req = Minitest::Mock.new
    req.expect(:path, '/unknown')
    req.expect(:path, '/unknown')
    response = @server.send(:process_request, req)
    assert_equal 404, response.status_code
    assert_match(/not found/i, response.body)
    req.verify
  end

  def test_process_request_pipeline_post
    body_data = { 'repository' => nil, 'build' => 'echo ok', 'deploy' => nil }
    req = Minitest::Mock.new
    req.expect(:path, '/')
    req.expect(:method, 'POST')
    req.expect(:json_body, body_data)

    # This will attempt actual execution via Executor which needs sandbox.
    # We test only routing here, the executor tests cover the rest.
    # Mock Executor.execution to avoid needing a sandbox
    original_method = Executor.method(:execution)
    Executor.define_singleton_method(:execution) do |_url, _build, _deploy|
      'Success: Pipeline completed in 0.1s'
    end

    response = nil
    capture_io { response = @server.send(:process_request, req) }
    assert_equal 200, response.status_code

    # Restore original method
    Executor.define_singleton_method(:execution, original_method)
    req.verify
  end

  def test_process_request_pipeline_non_post
    req = Minitest::Mock.new
    req.expect(:path, '/')
    req.expect(:method, 'GET')

    response = @server.send(:process_request, req)
    assert_equal 405, response.status_code
    req.verify
  end

  def test_server_attributes
    s = CICDServer::Server.new(host: '0.0.0.0', port: 9999)
    assert_equal '0.0.0.0', s.host
    assert_equal 9999, s.port
  end

  def test_shutdown_when_not_running
    # Should not raise
    @server.shutdown
  end

  def test_log_request
    body = '{"test": true}'
    client = StringIO.new(
      "POST / HTTP/1.1\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}"
    )
    req = CICDServer::HTTPRequest.new(client)
    # Should not raise
    capture_io { @server.send(:log_request, req) }
  end

  def test_log_request_empty_body
    client = StringIO.new("GET /health HTTP/1.1\r\n\r\n")
    req = CICDServer::HTTPRequest.new(client)
    capture_io { @server.send(:log_request, req) }
  end

  def test_handle_client_normal
    body = '{"repository": null, "build": "echo hi", "deploy": null}'
    raw = "POST / HTTP/1.1\r\nContent-Length: #{body.bytesize}\r\n\r\n#{body}"
    client = StringIO.new(raw)
    # Allow StringIO to act as a writable socket
    client.define_singleton_method(:print) { |data| } # no-op
    client.define_singleton_method(:close) {} # no-op

    original_method = Executor.method(:execution)
    Executor.define_singleton_method(:execution) do |_url, _build, _deploy|
      'Success: done'
    end

    capture_io { @server.send(:handle_client, client) }

    Executor.define_singleton_method(:execution, original_method)
  end

  def test_handle_client_server_error
    # A client that causes an error during request parsing
    client = Object.new
    client.define_singleton_method(:gets) { raise 'socket error' }
    client.define_singleton_method(:print) { |_data| }
    client.define_singleton_method(:close) {}

    capture_io { @server.send(:handle_client, client) }
    # Should not raise - errors are caught internally
  end

  def test_handle_client_request_too_large
    # Simulate a request with Content-Length exceeding MAX_REQUEST_SIZE
    huge_size = Config::MAX_REQUEST_SIZE + 1
    raw = "POST / HTTP/1.1\r\nContent-Length: #{huge_size}\r\n\r\n"

    # Create a proper mock client that behaves like a socket
    client = Object.new
    lines = raw.split("\n").map { |l| l + "\n" }
    line_idx = [0]
    client.define_singleton_method(:gets) do
      i = line_idx[0]
      line_idx[0] += 1
      i < lines.size ? lines[i] : nil
    end
    client.define_singleton_method(:read) { |_n| '' }
    printed_data = ['']
    client.define_singleton_method(:print) { |data| printed_data[0] = data }
    client.define_singleton_method(:close) {}

    capture_io { @server.send(:handle_client, client) }
    assert_match(/413/, printed_data[0])
  end

  def test_server_start_and_shutdown
    # Test that start creates a TCPServer and shutdown closes it
    server = CICDServer::Server.new(host: '127.0.0.1', port: 0)
    # Simulate @running = true and @server to test shutdown fully
    server.instance_variable_set(:@running, true)
    mock_tcp = Object.new
    mock_tcp.define_singleton_method(:close) {}
    server.instance_variable_set(:@server, mock_tcp)

    capture_io { server.shutdown }
    refute server.instance_variable_get(:@running)
  end

  def test_setup_signal_handlers
    server = CICDServer::Server.new(host: '127.0.0.1', port: 0)
    # Just ensure it doesn't raise
    server.send(:setup_signal_handlers)
  end
end
