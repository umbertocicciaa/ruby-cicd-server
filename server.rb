require 'socket'
require 'json'
require_relative 'executor'

server = TCPServer.new 8080
puts "Server running on http://localhost:8080"

loop do
  Thread.start(server.accept) do |client|

  request_line = client.gets
  puts "Request: #{request_line}"

  headers = {}
  while (line = client.gets) && line !~ /^\s*$/
    key, value = line.split(": ", 2)
    headers[key.strip] = value.strip if key && value
  end

  content_length = headers["Content-Length"].to_i
  body = content_length > 0 ? client.read(content_length) : ""
  puts "Raw body: #{body}"

  data = JSON.parse(body) rescue {}
  puts "Parsed JSON: #{data}"

  repository = data["repository"]
  build = data["build"]
  deploy = data["deploy"]
  
  begin
    result = Executor::execution(repository, build, deploy)
  rescue StandardError => e
    result = e
  end

  response_body = "#{result}"

  client.print <<~HTTP
    HTTP/1.1 200 OK
    Content-Type: text/plain
    Content-Length: #{response_body.bytesize}

    #{response_body}
  HTTP

  client.close
  end
end
