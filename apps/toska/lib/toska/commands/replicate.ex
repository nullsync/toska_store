defmodule Toska.Commands.Replicate do
  @moduledoc """
  Replication command for Toska.

  Starts a follower that keeps a local read replica of a leader.
  """

  @behaviour Toska.Commands.Command

  alias Toska.Commands.Command
  alias Toska.ConfigManager
  alias Toska.KVStore
  alias Toska.Replication.Follower

  @impl true
  def execute(args) do
    case args do
      ["--help"] ->
        show_help()

      ["-h"] ->
        show_help()

      ["status" | _rest] ->
        show_status()

      ["start" | rest] ->
        start_follower(rest)

      [] ->
        show_help()

      _ ->
        start_follower(args)
    end
  end

  @impl true
  def show_help do
    IO.puts("""
    Start a replication follower

    Usage:
      toska replicate start [options]
      toska replicate [options]

    Options:
      --leader URL        Leader base URL (required)
      --poll MS           Poll interval in milliseconds (default: 1000)
      --timeout MS        HTTP timeout in milliseconds (default: 5000)
      -d, --daemon        Run as background daemon process
      -h, --help          Show this help

    Examples:
      toska replicate start --leader http://localhost:4000
      toska replicate --leader http://localhost:4000 --poll 2000
      toska replicate --leader http://localhost:4000 --daemon
      toska replicate status
    """)

    :ok
  end

  defp start_follower(args) do
    {options, _remaining_args, invalid} = Command.parse_options(args, [
      leader: :string,
      poll: :integer,
      timeout: :integer,
      daemon: :boolean,
      help: :boolean
    ], [
      h: :help,
      d: :daemon
    ])

    cond do
      options[:help] ->
        show_help()

      invalid != [] ->
        Command.show_error("Invalid options: #{inspect(invalid)}")
        {:error, :invalid_options}

      true ->
        config = load_defaults()
        leader = options[:leader] || config["replica_url"]
        poll_ms = options[:poll] || config["replica_poll_interval_ms"] || 1000
        timeout_ms = options[:timeout] || config["replica_http_timeout_ms"] || 5000
        daemon = options[:daemon] || false
        daemon_child = daemon_child?()

        cond do
          not (is_binary(leader) and leader != "") ->
            Command.show_error("Leader URL is required (use --leader)")
            {:error, :missing_leader}

          daemon and not daemon_child ->
            start_daemon(leader, poll_ms, timeout_ms)

          true ->
            start_foreground(leader, poll_ms, timeout_ms, daemon_child)
        end
    end
  end

  defp start_foreground(leader, poll_ms, timeout_ms, daemon_child) do
    ensure_store()

    case Follower.start_link(
           leader_url: leader,
           poll_interval_ms: poll_ms,
           http_timeout_ms: timeout_ms
         ) do
      {:ok, _pid} ->
        Command.show_success("Replication follower started")
        Command.show_info("Leader: #{leader}")
        Command.show_info("Poll interval: #{poll_ms}ms")
        Command.show_info("HTTP timeout: #{timeout_ms}ms")
        if daemon_child do
          Command.show_info("Daemon mode active")
        end
        :timer.sleep(:infinity)

      {:error, {:already_started, _pid}} ->
        Command.show_error("Replication follower already running")
        {:error, :already_started}

      {:error, reason} ->
        Command.show_error("Failed to start follower: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp start_daemon(leader, poll_ms, timeout_ms) do
    case daemonize(leader, poll_ms, timeout_ms) do
      {:ok, log_path} ->
        Command.show_success("Replication follower daemon started successfully")
        Command.show_info("Log file: #{log_path}")
        :ok

      {:error, reason} ->
        Command.show_error("Failed to start daemon: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp ensure_store do
    case GenServer.whereis(KVStore) do
      nil -> KVStore.start_link()
      _pid -> :ok
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

  defp show_status do
    case Follower.status() do
      {:ok, status} ->
        IO.puts(Jason.encode!(status, pretty: true))
        :ok

      {:error, :not_running} ->
        Command.show_error("Replication follower is not running")
        {:error, :not_running}

      {:error, reason} ->
        Command.show_error("Failed to get follower status: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp daemon_child? do
    System.get_env("TOSKA_REPLICA_DAEMON") == "1"
  end

  defp daemonize(leader, poll_ms, timeout_ms) do
    log_path = daemon_log_path()
    File.mkdir_p!(Path.dirname(log_path))

    case build_daemon_command(leader, poll_ms, timeout_ms) do
      {:ok, {cmd, args, cd}} ->
        case System.find_executable("sh") do
          nil ->
            {:error, :shell_not_found}

          sh_path ->
            command = Enum.map([cmd | args], &shell_escape/1) |> Enum.join(" ")
            log = shell_escape(log_path)
            shell_command = "nohup #{command} > #{log} 2>&1 &"

            opts = [env: [{"TOSKA_REPLICA_DAEMON", "1"}], stderr_to_stdout: true]
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

  defp build_daemon_command(leader, poll_ms, timeout_ms) do
    args = [
      "replicate",
      "--leader",
      leader,
      "--poll",
      to_string(poll_ms),
      "--timeout",
      to_string(timeout_ms),
      "--daemon"
    ]

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
    Path.join([System.user_home(), ".toska", "toska_replica.log"])
  end

  defp shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\\''") <> "'"
  end
end
