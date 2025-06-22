# ToskaStore

A powerful Elixir-based HTTP server application built with Bandit and designed as an umbrella project. ToskaStore provides a robust CLI interface for server management along with HTTP endpoints for web-based interactions.

## Table of Contents

- [Installation & Setup](#installation--setup)
- [Dependencies](#dependencies)
- [Building](#building)
- [Testing](#testing)
- [Server Commands](#server-commands)
- [HTTP Endpoints](#http-endpoints)
- [Configuration Management](#configuration-management)
- [Development](#development)
- [Project Structure](#project-structure)

## Installation & Setup

### Prerequisites

- Elixir 1.18 or higher
- Erlang/OTP compatible version

### Getting Started

> **Important**: ToskaStore is an **umbrella project**. The CLI executable is built in the `apps/toska/` directory, not the root directory.

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd toska_store
   ```

2. **Install dependencies**
   ```bash
   mix deps.get
   ```

3. **Build the application**
   ```bash
   mix compile
   ```

4. **Build the CLI executable**
   
   Since this is an umbrella project, you have two options:
   
   **Option A: Build from the app directory (Recommended)**
   ```bash
   cd apps/toska
   mix escript.build
   # Creates: apps/toska/toska
   ```
   
   **Option B: Build from root with target app**
   ```bash
   # From the root directory
   MIX_TARGET_APP=toska mix escript.build
   # Creates: apps/toska/toska
   ```

5. **Create a convenient symlink (Optional)**
   ```bash
   # From the root directory, create a symlink for easier access
   ln -s apps/toska/toska ./toska
   ```

After building, you'll have a `toska` executable in the `apps/toska/` directory that provides the complete CLI interface.

## Dependencies

### Managing Dependencies

```bash
# Get all dependencies
mix deps.get

# Update dependencies
mix deps.update

# Update specific dependency
mix deps.update jason

# Clean dependencies
mix deps.clean

# Clean and reinstall all dependencies
mix deps.clean --all && mix deps.get

# Show dependency tree
mix deps.tree
```

### Main Dependencies

- **[Jason](https://hex.pm/packages/jason)** `~> 1.4` - JSON encoding/decoding
- **[Bandit](https://hex.pm/packages/bandit)** `~> 1.0` - HTTP server
- **[Plug](https://hex.pm/packages/plug)** `~> 1.15` - HTTP middleware and utilities

## Building

### Development Build

```bash
# Compile the application
mix compile

# Build with warnings as errors
mix compile --warnings-as-errors

# Force recompilation
mix compile --force
```

### Production Build

```bash
# Build for production
MIX_ENV=prod mix compile

# Build production escript
MIX_ENV=prod mix escript.build
```

### Escript Build

> **Important**: In umbrella projects, the escript is built in the app directory, not the root.

```bash
# Build from the toska app directory (Recommended)
cd apps/toska
mix escript.build
# Creates: apps/toska/toska

# OR build from root with target app
MIX_TARGET_APP=toska mix escript.build
# Creates: apps/toska/toska

# Production build
cd apps/toska
MIX_ENV=prod mix escript.build
```

**Executable Location**: The `toska` executable will be created at `apps/toska/toska`, not in the project root.

## Testing

```bash
# Run all tests
mix test

# Run tests with coverage
mix test --cover

# Run specific test file
mix test test/toska_test.exs

# Run tests in verbose mode
mix test --trace

# Run tests for specific environment
MIX_ENV=test mix test
```

## Server Commands

The ToskaStore CLI provides comprehensive server management capabilities.

> **Note**: The executable is located at `apps/toska/toska`. You can either:
> - Run commands as `./apps/toska/toska [command]`
> - Create a symlink with `ln -s apps/toska/toska ./toska` and use `./toska [command]`
> - Run from the app directory: `cd apps/toska && ./toska [command]`

### Start Server

Start the Toska HTTP server with various configuration options:

```bash
# Basic start (default: localhost:4000)
./apps/toska/toska start
# Or if you created a symlink:
./toska start

# Specify custom port
./apps/toska/toska start --port 8080
./apps/toska/toska start -p 3000

# Bind to all interfaces
./apps/toska/toska start --host 0.0.0.0 --port 8080

# Set environment
./apps/toska/toska start --env prod

# Run as daemon process
./apps/toska/toska start --daemon
./apps/toska/toska start -d

# Combined options
./apps/toska/toska start --host 0.0.0.0 --port 3000 --env prod --daemon

# Show help
./apps/toska/toska start --help
```

**Available Options:**
- `-p, --port PORT` - Port to bind the server (default: 4000)
- `--host HOST` - Host to bind the server (default: localhost)
- `--env ENV` - Environment to run in (default: dev)
- `-d, --daemon` - Run as daemon process
- `-h, --help` - Show command help

### Stop Server

Stop the running Toska server:

```bash
# Graceful stop
./apps/toska/toska stop

# Force stop
./apps/toska/toska stop --force
./apps/toska/toska stop -f

# Show help
./apps/toska/toska stop --help
```

**Available Options:**
- `-f, --force` - Force stop the server
- `-h, --help` - Show command help

### Server Status

Check the current status of the Toska server:

```bash
# Basic status
./apps/toska/toska status

# Verbose status with system information
./apps/toska/toska status --verbose
./apps/toska/toska status -v

# JSON output
./apps/toska/toska status --json
./apps/toska/toska status -j

# Show help
./apps/toska/toska status --help
```

**Available Options:**
- `-v, --verbose` - Show detailed status information
- `-j, --json` - Output status in JSON format
- `-h, --help` - Show command help

## HTTP Endpoints

When the server is running, the following HTTP endpoints are available:

### GET `/`
**Welcome Page** - Interactive HTML page showing server status and available endpoints
- **Response**: HTML page with server information
- **Status Code**: 200

### GET `/status`
**Server Status** - JSON endpoint returning detailed server status
- **Response**: JSON object with server status information
- **Status Code**: 200
- **Example Response**:
  ```json
  {
    "status": "running",
    "uptime": 45000,
    "config": {
      "host": "localhost",
      "port": 4000,
      "env": "dev",
      "daemon": false
    },
    "pid": "#PID<0.123.0>",
    "node": "nonode@nohost"
  }
  ```

### GET `/health`
**Health Check** - Health check endpoint for monitoring
- **Response**: JSON object with health status
- **Status Codes**: 
  - 200 (healthy/running)
  - 503 (unhealthy/starting/stopped)
- **Example Response**:
  ```json
  {
    "status": "healthy",
    "timestamp": 1640995200000,
    "uptime": 45000
  }
  ```

## Configuration Management

ToskaStore provides comprehensive configuration management through the CLI:

### View Configuration

```bash
# List all configuration
./apps/toska/toska config list

# List configuration in JSON format
./apps/toska/toska config list --json

# Get specific configuration value
./apps/toska/toska config get port
./apps/toska/toska config get host
./apps/toska/toska config get env
./apps/toska/toska config get log_level
```

### Update Configuration

```bash
# Set server port
./apps/toska/toska config set port 8080

# Set server host
./apps/toska/toska config set host "0.0.0.0"

# Set environment
./apps/toska/toska config set env prod

# Set log level
./apps/toska/toska config set log_level info
```

### Reset Configuration

```bash
# Reset specific configuration key
./apps/toska/toska config reset port

# Reset all configuration to defaults
./apps/toska/toska config reset

# Reset with confirmation skip
./apps/toska/toska config reset --confirm
./apps/toska/toska config reset -y
```

### Available Configuration Keys

- **port** - Server port (integer, default: 4000)
- **host** - Server host (string, default: "localhost")
- **env** - Environment (dev|test|prod, default: "dev")
- **log_level** - Log level (debug|info|warn|error, default: "info")

## Development

### Development Workflow

```bash
# Start development environment
mix deps.get
mix compile

# Build the CLI executable
cd apps/toska && mix escript.build

# Run tests during development
mix test --stale

# Start interactive shell
iex -S mix

# Format code
mix format

# Check for unused dependencies
mix deps.unlock --unused

# Generate documentation
mix docs
```

### Environment Variables

The application respects the following environment variables:

- `MIX_ENV` - Set the Mix environment (dev, test, prod)
- `PORT` - Override default port (when used programmatically)

### Code Organization

- **CLI Layer**: Command parsing and user interface (`lib/toska/cli.ex`, `lib/toska/commands/`)
- **Server Layer**: HTTP server management (`lib/toska/server.ex`)
- **HTTP Layer**: Request routing and handling (`lib/toska/router.ex`)
- **Configuration**: Configuration management (`lib/toska/config_manager.ex`)

## Project Structure

ToskaStore is organized as an Elixir umbrella application:

```
toska_store/
├── mix.exs                    # Umbrella project configuration
├── mix.lock                   # Dependency lock file
├── README.md                  # This file
├── config/
│   └── config.exs            # Application configuration
└── apps/
    └── toska/                # Main application
        ├── mix.exs           # Application-specific configuration
        ├── lib/
        │   ├── toska.ex      # Main application module
        │   └── toska/
        │       ├── application.ex      # OTP application
        │       ├── cli.ex             # CLI entry point
        │       ├── server.ex          # Server management
        │       ├── router.ex          # HTTP routing
        │       ├── command_parser.ex  # Command parsing
        │       ├── config_manager.ex  # Configuration
        │       └── commands/          # Individual commands
        │           ├── command.ex     # Command behaviour
        │           ├── start.ex       # Start command
        │           ├── stop.ex        # Stop command
        │           ├── status.ex      # Status command
        │           └── config.ex      # Config command
        └── test/             # Test files
```

### Key Components

- **Umbrella Application**: Allows for modular development and potential future expansion
- **OTP Application**: Full OTP compliance with supervised processes
- **GenServer Architecture**: Robust server state management
- **Escript**: Self-contained executable for easy deployment
- **Plug/Bandit**: Modern HTTP stack for performance and reliability

## Quick Start Examples

```bash
# 1. Setup and build
mix deps.get && cd apps/toska && mix escript.build && cd ../..

# 2. Create a convenient symlink (optional)
ln -s apps/toska/toska ./toska

# 3. Start server on custom port
./apps/toska/toska start --port 8080
# Or with symlink: ./toska start --port 8080

# 4. Check status (in another terminal)
./apps/toska/toska status --verbose

# 5. Test HTTP endpoints
curl http://localhost:8080/
curl http://localhost:8080/status
curl http://localhost:8080/health

# 6. Manage configuration
./apps/toska/toska config set port 9000
./apps/toska/toska config list

# 7. Stop server
./apps/toska/toska stop
```

### Alternative: Using from App Directory

```bash
# Work directly in the app directory
cd apps/toska

# Build executable
mix escript.build

# Run commands without path prefix
./toska start --port 8080
./toska status --verbose
./toska stop
```

---

**Version**: 0.1.0  
**License**: [Add your license]  
**Maintainers**: [Add maintainer information]
