defmodule Toska do
  @moduledoc """
  Toska - Command Line Interface for ToskaStore

  This module provides the main entry points and public API for the Toska CLI application.
  The CLI is designed to manage the Toska server process and handle various administrative tasks.

  ## Architecture

  The CLI is built with an extensible command structure:

  - `Toska.CommandParser` - Main command parser and router
  - `Toska.Commands.*` - Individual command implementations
  - `Toska.Server` - GenServer for managing the server process
  - `Toska.ConfigManager` - Configuration management

  ## Usage

  The CLI can be used in several ways:

  1. As an escript: `./toska start --port 8080`
  2. Via Mix: `mix run -e "Toska.run([\"start\", \"--port\", \"8080\"])"`
  3. Programmatically: `Toska.run(["status"])`

  ## Examples

      # Start the server
      Toska.run(["start", "--port", "8080"])

      # Check server status
      Toska.run(["status"])

      # Manage configuration
      Toska.run(["config", "set", "port", "9000"])
  """

  alias Toska.CommandParser

  @doc """
  Run a CLI command with the given arguments.

  This is the main entry point for programmatic usage of the CLI.

  ## Parameters

  - `args` - List of command arguments, similar to command line arguments

  ## Examples

      iex> Toska.run(["--help"])
      :ok

      iex> Toska.run(["status"])
      :ok
  """
  def run(args) when is_list(args) do
    CommandParser.parse(args)
  end

  @doc """
  Get version information for the CLI.
  """
  def version do
    case Application.spec(:toska, :vsn) do
      nil -> "0.1.0"
      vsn -> to_string(vsn)
    end
  end

  @doc """
  Check if the Toska server is running.
  """
  def server_running? do
    case Toska.Server.status() do
      %{status: :running} -> true
      _ -> false
    end
  end

  @doc """
  Get current server status information.
  """
  def server_status do
    Toska.Server.status()
  end
end
