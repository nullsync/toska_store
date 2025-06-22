# ToskaCli

A command-line interface for the Toska Store server, built with Elixir and designed for extensibility.

## Overview

ToskaCli provides a comprehensive command-line interface for managing the Toska server process. It includes commands for starting/stopping the server, checking status, and managing configuration.

## Architecture

The CLI is built with a modular, extensible architecture:

- **Command Parser** (`ToskaCli.CommandParser`) - Routes commands to appropriate handlers
- **Command Behavior** (`ToskaCli.Commands.Command`) - Defines common behavior for all commands
- **Individual Commands** (`ToskaCli.Commands.*`) - Specific command implementations
- **Server Management** (`ToskaCli.Server`) - GenServer for managing the server process
- **Configuration Management** (`ToskaCli.ConfigManager`) - Persistent configuration storage

## Installation

From the umbrella project root:

```bash
# Install dependencies
mix deps.get

# Compile the application
mix compile

# Build the escript (optional)
cd apps/toska_cli && mix escript.build
```

## Usage

### Via Mix (from umbrella root)

```bash
# Start the server
mix run -e "ToskaCli.run([\"start\", \"--port\", \"8080\"])"

# Check status
mix run -e "ToskaCli.run([\"status\"])"

# Show help
mix run -e "ToskaCli.run([\"--help\"])"
```

### Via Escript (from apps/toska_cli)

```bash
# Build the escript first
mix escript.build

# Run commands
./toska_cli start --port 8080
./toska_cli status
./toska_cli --help
```

### Programmatically

```elixir
# In an Elixir session or module
ToskaCli.run(["start", "--port", "8080"])
ToskaCli.run(["status"])
```

## Commands

### Global Options

- `-h, --help` - Show help information

### start

Start the Toska server with various options.

```bash
toska_cli start [options]

Options:
  -p, --port PORT     Port to bind the server (default: 4000)
  --host HOST         Host to bind the server (default: localhost)
  --env ENV           Environment to run in (default: dev)
  -d, --daemon        Run as daemon process
  -h, --help          Show this help

Examples:
  toska_cli start
  toska_cli start --port 8080
  toska_cli start --host 0.0.0.0 --port 3000
  toska_cli start --daemon
```

### stop

Stop the Toska server gracefully or forcefully.

```bash
toska_cli stop [options]

Options:
  -f, --force     Force stop the server
  -h, --help      Show this help

Examples:
  toska_cli stop
  toska_cli stop --force
```

### status

Display current server status and system information.

```bash
toska_cli status [options]

Options:
  -v, --verbose   Show detailed status information
  -j, --json      Output status in JSON format
  -h, --help      Show this help

Examples:
  toska_cli status
  toska_cli status --verbose
  toska_cli status --json
```

### config

Manage server configuration with subcommands.

```bash
toska_cli config <subcommand> [options]

Subcommands:
  get <key>           Get configuration value
  set <key> <value>   Set configuration value
  list                List all configuration
  reset [key]         Reset configuration to defaults

Examples:
  toska_cli config get port
  toska_cli config set port 8080
  toska_cli config set host "0.0.0.0"
  toska_cli config list
  toska_cli config reset port
  toska_cli config reset  # Reset all to defaults
```

## Configuration

Configuration is stored in `~/.toska/toska_config.json` and includes:

- **port** (integer): Server port (default: 4000)
- **host** (string): Server host (default: "localhost")
- **env** (string): Environment - dev|test|prod (default: "dev")
- **log_level** (string): Log level - debug|info|warn|error (default: "info")

## Development

### Adding New Commands

1. Create a new module in `lib/toska_cli/commands/` implementing the `ToskaCli.Commands.Command` behavior
2. Add the command route in `ToskaCli.CommandParser.parse/1`
3. Update help text and documentation

Example command structure:

```elixir
defmodule ToskaCli.Commands.MyCommand do
  @behaviour ToskaCli.Commands.Command
  
  alias ToskaCli.Commands.Command

  @impl true
  def execute(args) do
    # Parse options and execute command logic
    :ok
  end

  @impl true
  def show_help do
    IO.puts("Help text for my command")
    :ok
  end
end
```

### Running Tests

```bash
cd apps/toska_cli
mix test
```

### Code Quality

```bash
# Format code
mix format

# Check for issues
mix credo

# Type checking (if dialyzer is added)
mix dialyzer
```

## Server Process Foundation

The CLI includes a GenServer (`ToskaCli.Server`) that provides the foundation for the actual server process. This includes:

- Proper OTP supervision tree
- Configuration management
- Status monitoring
- Graceful shutdown handling

The server can be extended to include actual business logic, HTTP endpoints, database connections, etc.

## Extensibility

The CLI is designed for easy extension:

- **Commands**: Add new commands by implementing the Command behavior
- **Options**: Use OptionParser for consistent option handling
- **Configuration**: Extend the ConfigManager for new config keys
- **Server**: Extend the Server GenServer for additional functionality

## Future Enhancements

- Integration with external monitoring systems
- Plugin system for third-party commands
- Enhanced logging and metrics
- Clustering support
- Database integration
- HTTP API endpoints
