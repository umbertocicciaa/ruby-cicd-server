require 'socket'
require 'json'
require_relative 'executor'

server = TCPServer.new(8080)
puts "Server running on http://localhost:8080"

loop do
  client = server.accept

  request_line = client.gets

  headers = {}
  while (line = client.gets) != "\r\n"
    key, value = line.split(": ", 2)
    headers[key] = value.strip
  end

  content_length = headers["Content-Length"].to_i
  body = client.read(content_length)

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
