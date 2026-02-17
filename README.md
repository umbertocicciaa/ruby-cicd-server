# Ruby CI/CD Server

A lightweight, sandboxed CI/CD server built in pure Ruby with no external dependencies beyond the Ruby standard library.

## Features

### Security & Isolation

- **Linux Namespace Isolation**: Uses `unshare` for PID, mount, UTS, and IPC namespace isolation
- **Resource Limits**: CPU time, memory, process count, and file size limits
- **Sandboxed Execution**: Each pipeline runs in an isolated temporary workspace
- **Input Validation**: URL and command validation to prevent basic injection attacks
- **Request Size Limits**: Protection against large payload attacks

### Monitoring & Logging

- **Dual Logging**: Console output with colors + file logging with rotation
- **Pipeline Metrics**: Track success rates, execution times, and error patterns
- **Detailed Error Reporting**: Structured error messages with context
- **Execution Timing**: Precise timing for each pipeline step

### Architecture

- **Modular Design**: Separate concerns across modules
- **Exception Hierarchy**: Structured error handling with custom exceptions
- **Thread-Safe**: Handles concurrent requests via threaded connection handling
- **Graceful Shutdown**: Proper cleanup on SIGINT/SIGTERM
- **Configuration Management**: Environment-based configuration

### API Endpoints

- `POST /` - Execute CI/CD pipeline
- `GET /health` - Health check endpoint
- `GET /metrics` - View pipeline metrics

## Quick Start

```bash
ruby server.rb
```

Then trigger a build:

```bash
curl -X POST http://localhost:8080 \
  -H "Content-Type: application/json" \
  -d '{
    "repository": "https://github.com/dbarnett/python-helloworld",
    "build": "python3 --version"
  }'
```

## License

See LICENSE file
