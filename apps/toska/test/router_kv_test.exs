defmodule Toska.RouterKVTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  @opts Toska.Router.init([])

  setup do
    original_data_dir = System.get_env("TOSKA_DATA_DIR")
    tmp_dir = Path.join([System.tmp_dir!(), "toska_router_#{System.unique_integer([:positive])}"])

    File.mkdir_p!(tmp_dir)
    System.put_env("TOSKA_DATA_DIR", tmp_dir)

    stop_store()
    start_store()

    on_exit(fn ->
      stop_store()

      case original_data_dir do
        nil -> System.delete_env("TOSKA_DATA_DIR")
        value -> System.put_env("TOSKA_DATA_DIR", value)
      end

      File.rm_rf(tmp_dir)
    end)

    :ok
  end

  test "PUT/GET/DELETE flow" do
    put_conn =
      conn("PUT", "/kv/alpha", Jason.encode!(%{value: "1"}))
      |> put_req_header("content-type", "application/json")
      |> Toska.Router.call(@opts)

    assert put_conn.status == 200

    get_conn =
      conn("GET", "/kv/alpha")
      |> Toska.Router.call(@opts)

    assert get_conn.status == 200
    assert Jason.decode!(get_conn.resp_body)["value"] == "1"

    delete_conn =
      conn("DELETE", "/kv/alpha")
      |> Toska.Router.call(@opts)

    assert delete_conn.status == 200

    missing_conn =
      conn("GET", "/kv/alpha")
      |> Toska.Router.call(@opts)

    assert missing_conn.status == 404
  end

  test "mget returns values map" do
    :ok = Toska.KVStore.put("a", "1")
    :ok = Toska.KVStore.put("b", "2")

    conn =
      conn("POST", "/kv/mget", Jason.encode!(%{keys: ["a", "b", "c"]}))
      |> put_req_header("content-type", "application/json")
      |> Toska.Router.call(@opts)

    assert conn.status == 200
    values = Jason.decode!(conn.resp_body)["values"]
    assert values["a"] == "1"
    assert values["b"] == "2"
    assert is_nil(values["c"])
  end

  test "replication endpoints return data" do
    :ok = Toska.KVStore.put("replica", "ok")

    info_conn =
      conn("GET", "/replication/info")
      |> Toska.Router.call(@opts)

    assert info_conn.status == 200
    info = Jason.decode!(info_conn.resp_body)
    assert info["aof_path"]

    status_conn =
      conn("GET", "/replication/status")
      |> Toska.Router.call(@opts)

    assert status_conn.status in [200, 404]

    snapshot_conn =
      conn("GET", "/replication/snapshot")
      |> Toska.Router.call(@opts)

    assert snapshot_conn.status == 200
    snapshot = Jason.decode!(snapshot_conn.resp_body)
    assert snapshot["data"]

    aof_conn =
      conn("GET", "/replication/aof?since=0&max_bytes=1024")
      |> Toska.Router.call(@opts)

    assert aof_conn.status in [200, 204]

    if aof_conn.status == 200 do
      assert aof_conn.resp_body =~ "\"op\""
    end
  end

  defp stop_store do
    case GenServer.whereis(Toska.KVStore) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  defp start_store do
    child_spec = %{
      id: {:kv_store, System.unique_integer([:positive])},
      start: {Toska.KVStore, :start_link, [[]]},
      restart: :temporary
    }

    start_supervised!(child_spec)
  end
end
