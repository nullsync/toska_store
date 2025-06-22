defmodule Toska.Commands.Start do
  @moduledoc """
  Start command for Toska.

  Handles starting the Toska server with various configuration options.
  """

  @behaviour Toska.Commands.Command

  alias Toska.Commands.Command
  alias Toska.Server

  @impl true
  def execute(args) do
    {options, remaining_args, invalid} = Command.parse_options(args, [
      port: :integer,
      host: :string,
      env: :string,
      daemon: :boolean,
      help: :boolean
    ], [
      p: :port,
      h: :help,
      d: :daemon
    ])

    cond do
      options[:help] ->
        show_help()

      invalid != [] ->
        Command.show_error("Invalid options: #{inspect(invalid)}")
        show_help()
        {:error, :invalid_options}

      true ->
        start_server(options, remaining_args)
    end
  end

  @impl true
  def show_help do
    IO.puts("""
    Start the Toska server

    Usage:
      toska start [options]

    Options:
      -p, --port PORT     Port to bind the server (default: 4000)
      --host HOST         Host to bind the server (default: localhost)
      --env ENV           Environment to run in (default: dev)
      -d, --daemon        Run as daemon process
      -h, --help          Show this help

    Examples:
      toska start
      toska start --port 8080
      toska start --host 0.0.0.0 --port 3000
      toska start --daemon
    """)

    :ok
  end

  defp start_server(options, _remaining_args) do
    port = options[:port] || 4000
    host = options[:host] || "localhost"
    env = options[:env] || "dev"
    daemon = options[:daemon] || false

    Command.show_info("Starting Toska server...")
    Command.show_info("Host: #{host}")
    Command.show_info("Port: #{port}")
    Command.show_info("Environment: #{env}")

    if daemon do
      Command.show_info("Running as daemon process")
    end

    case Server.start(host: host, port: port, env: env, daemon: daemon) do
      {:ok, pid} ->
        Command.show_success("Server started successfully (PID: #{inspect(pid)})")
        if not daemon do
          Command.show_info("Press Ctrl+C to stop the server")
          :timer.sleep(:infinity)
        end
        :ok

      {:error, {:already_started, _pid}} ->
        Command.show_error("Server is already running")
        {:error, :already_started}

      {:error, reason} ->
        Command.show_error("Failed to start server: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
