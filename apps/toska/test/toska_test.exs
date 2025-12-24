defmodule ToskaTest do
  use ExUnit.Case
  doctest Toska

  alias Toska.TestHelpers

  test "run function exists" do
    assert function_exported?(Toska, :run, 1)
  end

  test "version returns a string" do
    assert is_binary(Toska.version())
  end

  test "server_running? returns false when stopped" do
    _ = Toska.Server.stop()
    refute Toska.server_running?()
  end

  test "server_running? returns true when running" do
    original_data_dir = System.get_env("TOSKA_DATA_DIR")
    tmp_dir = TestHelpers.tmp_dir("toska_running")

    File.mkdir_p!(tmp_dir)
    TestHelpers.put_env("TOSKA_DATA_DIR", tmp_dir)

    on_exit(fn ->
      _ = Toska.Server.stop()
      TestHelpers.restore_env("TOSKA_DATA_DIR", original_data_dir)
      File.rm_rf(tmp_dir)
    end)

    port = TestHelpers.free_port()
    assert {:ok, _pid} = Toska.Server.start(host: "127.0.0.1", port: port, env: "test")

    assert :ok =
             TestHelpers.wait_until(fn ->
               Toska.server_running?()
             end, 1500)
  end

  test "server_status returns a map" do
    status = Toska.server_status()
    assert is_map(status)
    assert Map.has_key?(status, :status)
  end
end
