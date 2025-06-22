defmodule Toska.CLI do
  @moduledoc """
  Main CLI entry point for Toska.

  This module serves as the escript entry point and handles the initial
  command parsing and delegation to appropriate command handlers.
  """

  alias Toska.CommandParser

  @doc """
  Main entry point for the CLI when run as an escript.
  """
  def main(args) do
    # Ensure the application is started
    Application.ensure_all_started(:toska)

    # Parse and execute the command
    case CommandParser.parse(args) do
      :ok ->
        System.halt(0)

      {:ok, _result} ->
        System.halt(0)

      {:error, _reason} ->
        System.halt(1)
    end
  end
end
