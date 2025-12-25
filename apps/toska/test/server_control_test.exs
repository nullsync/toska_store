defmodule Toska.ServerControlTest do
  use ExUnit.Case, async: false

  alias Toska.TestHelpers

  setup do
    original_home = System.get_env("HOME")
    tmp_home = TestHelpers.tmp_dir("toska_home")
    File.mkdir_p!(tmp_home)
    TestHelpers.put_env("HOME", tmp_home)

    on_exit(fn ->
      TestHelpers.restore_env("HOME", original_home)
      File.rm_rf(tmp_home)
    end)

    :ok
  end

  test "status falls back to local when remote is unreachable" do
    write_runtime("nosuch@localhost", "cookie")
    status = Toska.ServerControl.status()
    assert status.status == :stopped
  end

  test "status and stop use runtime metadata when available" do
    ensure_node_alive()
    cookie = Node.get_cookie()
    cookie = if cookie == :nocookie, do: :toska_cookie, else: cookie
    Node.set_cookie(cookie)

    write_runtime(Node.self(), cookie)

    status = Toska.ServerControl.status()
    assert status.status == :stopped

    assert {:error, :not_running} = Toska.ServerControl.stop()
  end

  test "local status and stop use running server" do
    original_data_dir = System.get_env("TOSKA_DATA_DIR")
    tmp_dir = TestHelpers.tmp_dir("toska_server_control")

    File.mkdir_p!(tmp_dir)
    TestHelpers.put_env("TOSKA_DATA_DIR", tmp_dir)

    on_exit(fn ->
      Toska.Server.stop()
      TestHelpers.restore_env("TOSKA_DATA_DIR", original_data_dir)
      File.rm_rf(tmp_dir)
    end)

    port = TestHelpers.free_port()
    assert {:ok, _pid} = Toska.Server.start(host: "127.0.0.1", port: port, env: "test")

    assert :ok =
             TestHelpers.wait_until(fn ->
               Toska.ServerControl.status().status == :running
             end, 2000)

    assert :ok = Toska.ServerControl.stop()
    assert :ok =
             TestHelpers.wait_until(fn ->
               Toska.Server.status().status == :stopped
             end, 2000)
  end

  test "stop returns not running when remote is unreachable" do
    write_runtime("nosuch@localhost", "cookie")
    assert {:error, :not_running} = Toska.ServerControl.stop()
  end

  defp write_runtime(node, cookie) do
    path = Toska.NodeControl.runtime_file_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{"node" => to_string(node), "cookie" => to_string(cookie)}))
  end

  defp ensure_node_alive do
    if Node.alive?() do
      :ok
    else
      case System.find_executable("epmd") do
        nil -> flunk("epmd not found")
        path -> System.cmd(path, ["-daemon"])
      end

      name = :"toska_test_#{System.unique_integer([:positive])}"

      case Node.start(name, :shortnames) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        {:error, reason} -> flunk("failed to start node: #{inspect(reason)}")
      end
    end
  end
end
