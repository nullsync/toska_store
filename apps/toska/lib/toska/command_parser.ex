defmodule Toska.CommandParser do
  @moduledoc """
  Command parser for Toska.

  Handles parsing of command-line arguments and routing to appropriate command handlers.
  """

  alias Toska.Commands

  @doc """
  Parse command line arguments and execute the appropriate command.

  ## Examples

      iex> Toska.CommandParser.parse(["start", "--port", "8080"])
      :ok

      iex> Toska.CommandParser.parse(["--help"])
      :ok
  """
  def parse(args) do
    case args do
      [] ->
        show_help()

      ["--help"] ->
        show_help()

      ["-h"] ->
        show_help()

      ["start" | rest] ->
        Commands.Start.execute(rest)

      ["stop" | rest] ->
        Commands.Stop.execute(rest)

      ["status" | rest] ->
        Commands.Status.execute(rest)

      ["config" | rest] ->
        Commands.Config.execute(rest)

      [command | _] ->
        IO.puts("Unknown command: #{command}")
        show_help()
        {:error, :unknown_command}
    end
  end

  @doc """
  Display help information for the CLI.
  """
  def show_help do
    IO.puts("""
    Toska - Command Line Interface for Toska Store

    Usage:
      toska [command] [options]

    Commands:
      start     Start the Toska server
      stop      Stop the Toska server
      status    Check server status
      config    Manage configuration

    Global Options:
      -h, --help    Show this help message

    Examples:
      toska start --port 8080
      toska stop
      toska status
      toska config get port
      toska config set port 9000

    For command-specific help, use:
      toska [command] --help
    """)

    :ok
  end
end
