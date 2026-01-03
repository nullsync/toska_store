defmodule Toska.ServerTest do
  use ExUnit.Case, async: false

  alias Toska.TestHelpers

  setup do
    original_data_dir = System.get_env("TOSKA_DATA_DIR")
    original_home = System.get_env("HOME")
    tmp_dir = TestHelpers.tmp_dir("toska_server")
    tmp_home = TestHelpers.tmp_dir("toska_home")

    File.mkdir_p!(tmp_dir)
    File.mkdir_p!(tmp_home)

    TestHelpers.put_env("TOSKA_DATA_DIR", tmp_dir)
    TestHelpers.put_env("HOME", tmp_home)

    stop_server()

    on_exit(fn ->
      stop_server()
      TestHelpers.restore_env("TOSKA_DATA_DIR", original_data_dir)
      TestHelpers.restore_env("HOME", original_home)
      File.rm_rf(tmp_dir)
      File.rm_rf(tmp_home)
    end)

    :ok
  end

  test "server lifecycle and config updates" do
    port = TestHelpers.free_port()

    assert {:ok, _pid} =
             Toska.Server.start(host: "127.0.0.1", port: port, env: "test", daemon: false)

    assert :ok =
             TestHelpers.wait_until(
               fn ->
                 Toska.Server.status().status == :running
               end,
               1500
             )

    assert {:ok, config} = Toska.Server.get_config()
    assert config.host == "127.0.0.1"
    assert config.port == port

    assert :ok = Toska.Server.update_config(%{env: "dev"})
    assert {:ok, updated} = Toska.Server.get_config()
    assert updated.env == "dev"

    assert :ok = Toska.Server.stop()

    assert :ok =
             TestHelpers.wait_until(
               fn ->
                 Toska.Server.status().status == :stopped
               end,
               1000
             )
  end

  test "start returns already started" do
    port = TestHelpers.free_port()

    assert {:ok, _pid} =
             Toska.Server.start(host: "127.0.0.1", port: port, env: "test", daemon: false)

    assert {:error, {:already_started, _pid}} =
             Toska.Server.start(host: "127.0.0.1", port: port, env: "test", daemon: false)

    assert :ok = Toska.Server.stop()
  end

  test "stop returns not running when server is stopped" do
    assert {:error, :not_running} = Toska.Server.stop()
  end

  test "get_config and update_config return errors when stopped" do
    assert {:error, :not_running} = Toska.Server.get_config()
    assert {:error, :not_running} = Toska.Server.update_config(%{env: "dev"})
  end

  test "start handles non-string host values" do
    port = TestHelpers.free_port()
    assert {:ok, _pid} = Toska.Server.start(host: 123, port: port, env: "test", daemon: false)
    assert :ok = Toska.Server.stop()
  end

  test "start accepts invalid host values" do
    port = TestHelpers.free_port()

    assert {:ok, _pid} =
             Toska.Server.start(host: "not-an-ip", port: port, env: "test", daemon: false)

    assert :ok = Toska.Server.stop()
  end

  defp stop_server do
    TestHelpers.safe_stop_server()
  end
end
