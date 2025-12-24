defmodule Toska.CommandsTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Toska.TestHelpers

  setup do
    original_config_dir = System.get_env("TOSKA_CONFIG_DIR")
    was_started = app_started?(:toska)
    tmp_dir = TestHelpers.tmp_dir("toska_cmd_cfg")

    File.mkdir_p!(tmp_dir)
    stop_app(:toska)
    TestHelpers.put_env("TOSKA_CONFIG_DIR", tmp_dir)
    Application.ensure_all_started(:toska)
    stop_server()

    on_exit(fn ->
      stop_server()
      stop_app(:toska)
      TestHelpers.restore_env("TOSKA_CONFIG_DIR", original_config_dir)
      if was_started do
        Application.ensure_all_started(:toska)
      end
      File.rm_rf(tmp_dir)
    end)

    :ok
  end

  test "start command shows help" do
    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Start.execute(["--help"])
      end)

    assert output =~ "Start the Toska server"
  end

  test "start command rejects invalid options" do
    output =
      capture_io(:stderr, fn ->
        assert {:error, :invalid_options} = Toska.Commands.Start.execute(["--port", "nope"])
      end)

    assert output =~ "Invalid options"
  end

  test "start command daemon reports missing mix" do
    original_path = System.get_env("PATH")
    TestHelpers.put_env("PATH", "")

    on_exit(fn ->
      TestHelpers.restore_env("PATH", original_path)
    end)

    output =
      capture_io(:stderr, fn ->
        assert {:error, :mix_not_found} =
                 Toska.Commands.Start.execute([
                   "--daemon",
                   "--host",
                   "127.0.0.1",
                   "--port",
                   "4010",
                   "--env",
                   "test"
                 ])
      end)

    assert output =~ "Failed to start daemon"
  end

  test "start command reports already running" do
    port = TestHelpers.free_port()
    {:ok, _pid} = Toska.Server.start(host: "127.0.0.1", port: port, env: "test")

    output =
      capture_io(:stderr, fn ->
        assert {:error, :already_started} =
                 Toska.Commands.Start.execute(["--port", Integer.to_string(port), "--host", "127.0.0.1"])
      end)

    assert output =~ "already running"
  end

  test "start command daemon reports already running" do
    port = TestHelpers.free_port()
    {:ok, _pid} = Toska.Server.start(host: "127.0.0.1", port: port, env: "test")

    assert :ok =
             TestHelpers.wait_until(fn ->
               Toska.Server.status().status == :running
             end, 2000)

    output =
      capture_io(:stderr, fn ->
        assert {:error, :already_started} =
                 Toska.Commands.Start.execute([
                   "--daemon",
                   "--port",
                   Integer.to_string(port),
                   "--host",
                   "127.0.0.1",
                   "--env",
                   "test"
                 ])
      end)

    assert output =~ "already running"
    assert :ok = Toska.Server.stop()
  end

  test "start command starts server in foreground" do
    port = TestHelpers.free_port()

    task =
      Task.async(fn ->
        Toska.Commands.Start.execute(["--port", Integer.to_string(port), "--host", "127.0.0.1", "--env", "test"])
      end)

    assert :ok =
             TestHelpers.wait_until(fn ->
               Toska.Server.status().status == :running
             end, 2000)

    assert :ok = Toska.Server.stop()
    Task.shutdown(task, :brutal_kill)
  end

  test "start command daemon reports missing shell" do
    mix_path = System.find_executable("mix")
    assert is_binary(mix_path)

    tmp_bin = TestHelpers.tmp_dir("toska_bin")
    File.mkdir_p!(tmp_bin)
    mix_target = Path.join(tmp_bin, "mix")
    File.cp!(mix_path, mix_target)
    File.chmod!(mix_target, 0o755)

    original_path = System.get_env("PATH")
    TestHelpers.put_env("PATH", tmp_bin)

    on_exit(fn ->
      TestHelpers.restore_env("PATH", original_path)
      File.rm_rf(tmp_bin)
    end)

    output =
      capture_io(:stderr, fn ->
        assert {:error, :shell_not_found} =
                 Toska.Commands.Start.execute([
                   "--daemon",
                   "--host",
                   "127.0.0.1",
                   "--port",
                   "4011",
                   "--env",
                   "test"
                 ])
      end)

    assert output =~ "Failed to start daemon"
  end

  test "start command daemon child blocks while server runs" do
    original_daemon = System.get_env("TOSKA_DAEMON")
    TestHelpers.put_env("TOSKA_DAEMON", "1")

    on_exit(fn ->
      TestHelpers.restore_env("TOSKA_DAEMON", original_daemon)
    end)

    port = TestHelpers.free_port()

    task =
      Task.async(fn ->
        Toska.Commands.Start.execute([
          "--daemon",
          "--port",
          Integer.to_string(port),
          "--host",
          "127.0.0.1",
          "--env",
          "test"
        ])
      end)

    assert :ok =
             TestHelpers.wait_until(fn ->
               Toska.Server.status().status == :running
             end, 2000)

    assert :ok = Toska.Server.stop()
    Task.shutdown(task, :brutal_kill)
  end

  test "stop command shows help" do
    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Stop.execute(["--help"])
      end)

    assert output =~ "Stop the Toska server"
  end

  test "stop command prints force mode for stopped server" do
    output =
      capture_io(fn ->
        assert {:error, :not_running} = Toska.Commands.Stop.execute(["--force"])
      end)

    assert output =~ "Force stopping server"
  end

  test "stop command returns not running" do
    output =
      capture_io(:stderr, fn ->
        assert {:error, :not_running} = Toska.Commands.Stop.execute([])
      end)

    assert output =~ "not currently running"
  end

  test "stop command stops running server" do
    port = TestHelpers.free_port()
    {:ok, _pid} = Toska.Server.start(host: "127.0.0.1", port: port, env: "test")

    assert :ok = Toska.Commands.Stop.execute([])
    assert Toska.Server.status().status == :stopped
  end

  test "status command supports json output" do
    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Status.execute(["--json"])
      end)

    decoded = Jason.decode!(output)
    assert Map.has_key?(decoded, "server_status")
    assert Map.has_key?(decoded, "timestamp")
  end

  test "status command shows help" do
    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Status.execute(["--help"])
      end)

    assert output =~ "Show the status of the Toska server"
  end

  test "status command prints default text output" do
    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Status.execute([])
      end)

    assert output =~ "Toska Server Status"
  end

  test "status command shows uptime when server is running" do
    port = TestHelpers.free_port()
    {:ok, _pid} = Toska.Server.start(host: "127.0.0.1", port: port, env: "test")

    assert :ok =
             TestHelpers.wait_until(fn ->
               Toska.Server.status().status == :running
             end, 2000)

    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Status.execute([])
      end)

    assert output =~ "Uptime:"

    assert :ok = Toska.Server.stop()
  end

  test "status command supports verbose output" do
    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Status.execute(["--verbose"])
      end)

    assert output =~ "System Information"
    assert output =~ "Toska Server Status"
  end

  test "config command reports missing subcommand" do
    output =
      capture_io(:stderr, fn ->
        assert {:error, :missing_subcommand} = Toska.Commands.Config.execute([])
      end)

    assert output =~ "Config command requires a subcommand"
  end

  test "config command rejects unknown subcommand" do
    output =
      capture_io(:stderr, fn ->
        assert {:error, :unknown_subcommand} = Toska.Commands.Config.execute(["nope"])
      end)

    assert output =~ "Unknown config subcommand"
  end

  test "config command validates arguments" do
    output =
      capture_io(:stderr, fn ->
        assert {:error, :invalid_args} = Toska.Commands.Config.execute(["get"])
      end)

    assert output =~ "Get command requires exactly one key"
  end

  test "config command get/set/list/reset help" do
    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Config.execute(["get", "--help"])
      end)

    assert output =~ "Get a configuration value"

    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Config.execute(["set", "--help"])
      end)

    assert output =~ "Set a configuration value"

    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Config.execute(["list", "--help"])
      end)

    assert output =~ "List all configuration values"

    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Config.execute(["reset", "--help"])
      end)

    assert output =~ "Reset configuration to defaults"
  end

  test "config command get reports missing keys" do
    output =
      capture_io(:stderr, fn ->
        assert {:error, :not_found} = Toska.Commands.Config.execute(["get", "missing_key"])
      end)

    assert output =~ "not found"
  end

  test "config command set reports invalid values" do
    output =
      capture_io(:stderr, fn ->
        assert {:error, _} = Toska.Commands.Config.execute(["set", "port", "0"])
      end)

    assert output =~ "Failed to set configuration"
  end

  test "config command set/get/list/reset succeed" do
    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Config.execute(["set", "port", "4020"])
      end)

    assert output =~ "Configuration updated"

    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Config.execute(["get", "port"])
      end)

    assert output =~ "port:"

    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Config.execute(["list"])
      end)

    assert output =~ "Current Configuration:"

    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Config.execute(["reset", "port"])
      end)

    assert output =~ "Reset port to default"
  end

  test "config command list outputs json" do
    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Config.execute(["list", "--json"])
      end)

    decoded = Jason.decode!(output)
    assert Map.has_key?(decoded, "port")
  end

  test "config command reset all can be cancelled" do
    output =
      capture_io("n\n", fn ->
        assert :ok = Toska.Commands.Config.execute(["reset"])
      end)

    assert output =~ "reset cancelled"
  end

  test "config command reset reports partial failures" do
    output =
      capture_io(:stderr, fn ->
        assert {:error, :partial_failure} =
                 Toska.Commands.Config.execute(["reset", "port", "unknown_key"])
      end)

    assert output =~ "Failed to reset"
  end

  test "config command reset all with confirm" do
    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Config.execute(["reset", "--confirm"])
      end)

    assert output =~ "All configuration reset"
  end

  test "replicate command rejects missing leader" do
    output =
      capture_io(:stderr, fn ->
        assert {:error, :missing_leader} = Toska.Commands.Replicate.execute(["--leader", ""])
      end)

    assert output =~ "Leader URL is required"
  end

  test "replicate command shows help" do
    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Replicate.execute(["--help"])
      end)

    assert output =~ "Start a replication follower"
  end

  test "replicate command shows help with no args" do
    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Replicate.execute([])
      end)

    assert output =~ "Start a replication follower"
  end

  test "replicate command shows help with -h" do
    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Replicate.execute(["-h"])
      end)

    assert output =~ "Start a replication follower"
  end

  test "replicate command rejects invalid options" do
    output =
      capture_io(:stderr, fn ->
        assert {:error, :invalid_options} =
                 Toska.Commands.Replicate.execute(["--leader", "http://localhost", "--poll", "bad"])
      end)

    assert output =~ "Invalid options"
  end

  test "replicate command status fails when not running" do
    output =
      capture_io(:stderr, fn ->
        assert {:error, :not_running} = Toska.Commands.Replicate.execute(["status"])
      end)

    assert output =~ "not running"
  end

  test "replicate command reports already running" do
    {:ok, _} = Toska.TestLeaderState.start_link()
    port = TestHelpers.free_port()
    {:ok, bandit_pid} = Bandit.start_link(plug: Toska.TestLeaderPlug, port: port)
    leader_url = "http://localhost:#{port}"

    {:ok, _pid} =
      Toska.Replication.Follower.start_link(
        leader_url: leader_url,
        poll_interval_ms: 100,
        http_timeout_ms: 1000
      )

    output =
      capture_io(:stderr, fn ->
        assert {:error, :already_started} =
                 Toska.Commands.Replicate.execute(["--leader", leader_url, "--poll", "50"])
      end)

    assert output =~ "already running"

    stop_follower()
    stop_leader_state()
    stop_bandit(bandit_pid)
  end

  test "replicate command daemon reports missing shell" do
    mix_path = System.find_executable("mix")
    assert is_binary(mix_path)

    tmp_bin = TestHelpers.tmp_dir("toska_bin")
    File.mkdir_p!(tmp_bin)
    mix_target = Path.join(tmp_bin, "mix")
    File.cp!(mix_path, mix_target)
    File.chmod!(mix_target, 0o755)

    original_path = System.get_env("PATH")
    TestHelpers.put_env("PATH", tmp_bin)

    on_exit(fn ->
      TestHelpers.restore_env("PATH", original_path)
      File.rm_rf(tmp_bin)
    end)

    output =
      capture_io(:stderr, fn ->
        assert {:error, :shell_not_found} =
                 Toska.Commands.Replicate.execute([
                   "--daemon",
                   "--leader",
                   "http://localhost"
                 ])
      end)

    assert output =~ "Failed to start daemon"
  end

  test "replicate command daemon child blocks while follower runs" do
    original_daemon = System.get_env("TOSKA_REPLICA_DAEMON")
    TestHelpers.put_env("TOSKA_REPLICA_DAEMON", "1")

    on_exit(fn ->
      TestHelpers.restore_env("TOSKA_REPLICA_DAEMON", original_daemon)
    end)

    {:ok, _} = Toska.TestLeaderState.start_link()
    port = TestHelpers.free_port()
    {:ok, bandit_pid} = Bandit.start_link(plug: Toska.TestLeaderPlug, port: port)
    leader_url = "http://localhost:#{port}"

    task =
      Task.async(fn ->
        Toska.Commands.Replicate.execute(["--leader", leader_url, "--poll", "50"])
      end)

    assert :ok =
             TestHelpers.wait_until(fn ->
               match?({:ok, _}, Toska.Replication.Follower.status())
             end, 2000)

    stop_follower()
    Task.shutdown(task, :brutal_kill)
    stop_leader_state()
    stop_bandit(bandit_pid)
  end

  test "replicate command starts follower and reports status" do
    {:ok, _} = Toska.TestLeaderState.start_link()
    port = TestHelpers.free_port()
    {:ok, bandit_pid} = Bandit.start_link(plug: Toska.TestLeaderPlug, port: port)
    leader_url = "http://localhost:#{port}"

    task =
      Task.async(fn ->
        Toska.Commands.Replicate.execute([
          "start",
          "--leader",
          leader_url,
          "--poll",
          "50",
          "--timeout",
          "1000"
        ])
      end)

    assert :ok =
             TestHelpers.wait_until(fn ->
               match?({:ok, _}, Toska.Replication.Follower.status())
             end, 2000)

    output =
      capture_io(fn ->
        assert :ok = Toska.Commands.Replicate.execute(["status"])
      end)

    assert output =~ leader_url

    stop_follower()
    Task.shutdown(task, :brutal_kill)
    stop_leader_state()
    stop_bandit(bandit_pid)
  end

  test "command helpers print output" do
    output =
      capture_io(fn ->
        Toska.Commands.Command.show_info("info")
        Toska.Commands.Command.show_success("ok")
      end)

    assert output =~ "info"
    assert output =~ "ok"

    output =
      capture_io(:stderr, fn ->
        Toska.Commands.Command.show_error("bad")
      end)

    assert output =~ "bad"
  end

  defp stop_server do
    case Toska.Server.stop() do
      :ok -> :ok
      {:error, :not_running} -> :ok
      {:error, _} -> :ok
    end
  end

  defp app_started?(app) do
    Enum.any?(Application.started_applications(), fn {name, _, _} -> name == app end)
  end

  defp stop_app(app) do
    if app_started?(app) do
      Application.stop(app)
    end

    :ok
  end

  defp stop_follower do
    case GenServer.whereis(Toska.Replication.Follower) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  defp stop_leader_state do
    case Process.whereis(Toska.TestLeaderState) do
      nil -> :ok
      pid -> Agent.stop(pid)
    end
  end

  defp stop_bandit(pid) do
    try do
      GenServer.stop(pid)
    catch
      :exit, _ -> :ok
    end
  end
end
