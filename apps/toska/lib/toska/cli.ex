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
    main(args, &System.halt/1)
  end

  def main(args, halt_fun) when is_list(args) and is_function(halt_fun, 1) do
    # Ensure the application is started
    Application.ensure_all_started(:toska)

    # Parse and execute the command
    case CommandParser.parse(args) do
      :ok ->
        halt_fun.(0)

      {:ok, _result} ->
        halt_fun.(0)

      {:error, _reason} ->
        halt_fun.(1)
    end
  end
end
