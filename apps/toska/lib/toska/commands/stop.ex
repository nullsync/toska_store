defmodule Toska.Commands.Stop do
  @moduledoc """
  Stop command for Toska.

  Handles stopping the Toska server gracefully.
  """

  @behaviour Toska.Commands.Command

  alias Toska.Commands.Command
  alias Toska.ServerControl

  @impl true
  def execute(args) do
    {options, remaining_args, invalid} = Command.parse_options(args, [
      force: :boolean,
      help: :boolean
    ], [
      f: :force,
      h: :help
    ])

    cond do
      options[:help] ->
        show_help()

      invalid != [] ->
        Command.show_error("Invalid options: #{inspect(invalid)}")
        show_help()
        {:error, :invalid_options}

      true ->
        stop_server(options, remaining_args)
    end
  end

  @impl true
  def show_help do
    IO.puts("""
    Stop the Toska server

    Usage:
      toska stop [options]

    Options:
      -f, --force     Force stop the server
      -h, --help      Show this help

    Examples:
      toska stop
      toska stop --force
    """)

    :ok
  end

  defp stop_server(options, _remaining_args) do
    force = options[:force] || false

    Command.show_info("Stopping Toska server...")

    if force do
      Command.show_info("Force stopping server")
    end

    case ServerControl.stop(force: force) do
      :ok ->
        Command.show_success("Server stopped successfully")
        :ok

      {:error, :not_running} ->
        Command.show_error("Server is not currently running")
        {:error, :not_running}

      {:error, reason} ->
        Command.show_error("Failed to stop server: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
