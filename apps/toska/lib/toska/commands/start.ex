defmodule Toska.Commands.Start do
  @moduledoc """
  Start command for Toska.

  Handles starting the Toska server with various configuration options.
  """

  @behaviour Toska.Commands.Command

  alias Toska.Commands.Command
  alias Toska.ConfigManager
  alias Toska.Server
  alias Toska.ServerControl

  @impl true
  def execute(args) do
    {options, remaining_args, invalid} =
      Command.parse_options(
        args,
        [
          port: :integer,
          host: :string,
          env: :string,
          daemon: :boolean,
          help: :boolean
        ],
        p: :port,
        h: :help,
        d: :daemon
      )

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
      -p, --port PORT     Port to bind the server (default: config port or 4000)
      --host HOST         Host to bind the server (default: config host or localhost)
      --env ENV           Environment to run in (default: config env or dev)
      -d, --daemon        Run as background daemon process
      -h, --help          Show this help

    Examples:
      toska start
      toska start --port 8080
      toska start --host 0.0.0.0 --port 3000
      toska start --daemon

    Daemon logs: ~/.toska/toska_daemon.log
    """)

    :ok
  end

  defp start_server(options, _remaining_args) do
    defaults = load_defaults()
    port = options[:port] || Map.get(defaults, "port", 4000)
    host = options[:host] || Map.get(defaults, "host", "localhost")
    env = options[:env] || Map.get(defaults, "env", "dev")
    daemon = options[:daemon] || false
    daemon_child = daemon_child?()

    if daemon and not daemon_child do
      Command.show_info("Starting Toska server in daemon mode...")
    else
      Command.show_info("Starting Toska server...")
    end

    Command.show_info("Host: #{host}")
    Command.show_info("Port: #{port}")
    Command.show_info("Environment: #{env}")

    if daemon and daemon_child do
      Command.show_info("Daemon mode active")
    end

    cond do
      daemon and not daemon_child ->
        start_daemon(host, port, env)

      true ->
        start_foreground(host, port, env, daemon, daemon_child)
    end
  end

  defp start_foreground(host, port, env, daemon, daemon_child) do
    case Server.start(host: host, port: port, env: env, daemon: daemon) do
      {:ok, pid} ->
        Command.show_success("Server started successfully (PID: #{inspect(pid)})")

        if should_block?(daemon, daemon_child) do
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

  defp start_daemon(host, port, env) do
    case ServerControl.status() do
      %{status: :running} ->
        Command.show_error("Server is already running")
        {:error, :already_started}

      _ ->
        case daemonize(host, port, env) do
          {:ok, log_path} ->
            Command.show_success("Server daemon started successfully")
            Command.show_info("Log file: #{log_path}")
            :ok

          {:error, reason} ->
            Command.show_error("Failed to start daemon: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp load_defaults do
    case GenServer.whereis(ConfigManager) do
      nil ->
        %{}

      _pid ->
        case ConfigManager.list() do
          {:ok, config} -> config
          _ -> %{}
        end
    end
  end

  defp daemonize(host, port, env) do
    log_path = daemon_log_path()
    File.mkdir_p!(Path.dirname(log_path))

    case build_daemon_command(host, port, env) do
      {:ok, {cmd, args, cd}} ->
        case System.find_executable("sh") do
          nil ->
            {:error, :shell_not_found}

          sh_path ->
            command = Enum.map([cmd | args], &shell_escape/1) |> Enum.join(" ")
            log = shell_escape(log_path)
            shell_command = "nohup #{command} > #{log} 2>&1 &"

            opts = [env: [{"TOSKA_DAEMON", "1"}], stderr_to_stdout: true]
            opts = if cd, do: Keyword.put(opts, :cd, cd), else: opts

            {_output, status} = System.cmd(sh_path, ["-c", shell_command], opts)

            if status == 0 do
              {:ok, log_path}
            else
              {:error, {:daemon_start_failed, status}}
            end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_daemon_command(host, port, env) do
    args = ["start", "--host", host, "--port", to_string(port), "--env", env, "--daemon"]

    case escript_path() do
      nil ->
        case find_mix_root(File.cwd!()) do
          nil ->
            {:error, :mix_project_not_found}

          root ->
            case System.find_executable("mix") do
              nil ->
                {:error, :mix_not_found}

              mix_path ->
                expr = "Toska.run(#{inspect(args)})"
                {:ok, {mix_path, ["run", "-e", expr], root}}
            end
        end

      path ->
        if File.exists?(path) do
          {:ok, {path, args, nil}}
        else
          {:error, :escript_not_found}
        end
    end
  end

  defp escript_path do
    if function_exported?(:escript, :script_name, 0) do
      case :escript.script_name() do
        :undefined -> nil
        name -> Path.expand(List.to_string(name))
      end
    else
      nil
    end
  end

  defp find_mix_root(dir) do
    if File.exists?(Path.join(dir, "mix.exs")) do
      dir
    else
      parent = Path.dirname(dir)
      if parent == dir, do: nil, else: find_mix_root(parent)
    end
  end

  defp daemon_log_path do
    Path.join([System.user_home(), ".toska", "toska_daemon.log"])
  end

  defp daemon_child? do
    System.get_env("TOSKA_DAEMON") == "1"
  end

  defp should_block?(daemon, daemon_child) do
    not daemon or daemon_child
  end

  defp shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\\''") <> "'"
  end
end
