defmodule Toska.Commands.Command do
  @moduledoc """
  Behavior for CLI commands.

  All command modules should implement this behavior to ensure consistency
  and extensibility across the CLI interface.
  """

  @doc """
  Execute the command with the given arguments.

  Returns:
    - :ok on success
    - {:ok, result} on success with a result
    - {:error, reason} on failure
  """
  @callback execute(args :: [String.t()]) :: :ok | {:ok, any()} | {:error, any()}

  @doc """
  Show help for the specific command.
  """
  @callback show_help() :: :ok

  @doc """
  Parse command-specific options using OptionParser.

  This is a helper function that commands can use to parse their specific options.
  """
  def parse_options(args, switches \\ [], aliases \\ []) do
    OptionParser.parse(args, switches: switches, aliases: aliases)
  end

  @doc """
  Display an error message in a consistent format.
  """
  def show_error(message) do
    IO.puts(:stderr, "Error: #{message}")
  end

  @doc """
  Display a success message in a consistent format.
  """
  def show_success(message) do
    IO.puts("✓ #{message}")
  end

  @doc """
  Display an info message in a consistent format.
  """
  def show_info(message) do
    IO.puts("ℹ #{message}")
  end
end
