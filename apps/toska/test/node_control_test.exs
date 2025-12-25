defmodule Toska.NodeControlTest do
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

  test "runtime file path uses user home" do
    path = Toska.NodeControl.runtime_file_path()
    assert String.contains?(path, Path.join([".toska", "toska_runtime.json"]))
    assert String.starts_with?(path, System.user_home())
  end

  test "connect returns error when runtime is missing" do
    Toska.NodeControl.clear_runtime()
    assert {:error, :no_runtime} = Toska.NodeControl.connect()
  end

  test "connect returns error for invalid runtime content" do
    path = Toska.NodeControl.runtime_file_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{"node" => "toska@host"}))

    assert {:error, :invalid_runtime} = Toska.NodeControl.connect()
  end

  test "connect returns error for malformed runtime content" do
    path = Toska.NodeControl.runtime_file_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "{")

    assert {:error, _} = Toska.NodeControl.connect()
  end

  test "connect returns unreachable for missing node" do
    write_runtime("nosuch@localhost", "cookie")
    assert {:error, :unreachable} = Toska.NodeControl.connect()
  end

  test "ensure_server_node writes runtime and connect succeeds" do
    assert :ok = Toska.NodeControl.ensure_server_node()
    path = Toska.NodeControl.runtime_file_path()
    assert File.exists?(path)

    payload = Jason.decode!(File.read!(path))
    assert payload["node"]
    assert payload["cookie"]

    assert {:ok, node} = Toska.NodeControl.connect()
    assert is_atom(node)
  end

  test "clear_runtime succeeds when missing" do
    assert :ok = Toska.NodeControl.clear_runtime()
  end

  test "clear_runtime removes runtime file" do
    path = Toska.NodeControl.runtime_file_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{"node" => "toska@host", "cookie" => "cookie"}))

    assert File.exists?(path)
    assert :ok = Toska.NodeControl.clear_runtime()
    refute File.exists?(path)
  end

  defp write_runtime(node, cookie) do
    path = Toska.NodeControl.runtime_file_path()
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{"node" => node, "cookie" => cookie}))
  end
end
