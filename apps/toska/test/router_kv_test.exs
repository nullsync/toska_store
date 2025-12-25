defmodule Toska.RouterKVTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  alias Toska.TestHelpers

  @opts Toska.Router.init([])

  setup do
    original_data_dir = System.get_env("TOSKA_DATA_DIR")
    original_auth_token = System.get_env("TOSKA_AUTH_TOKEN")
    original_rate_limit_per = System.get_env("TOSKA_RATE_LIMIT_PER_SEC")
    original_rate_limit_burst = System.get_env("TOSKA_RATE_LIMIT_BURST")
    original_replica_url = System.get_env("TOSKA_REPLICA_URL")
    tmp_dir = Path.join([System.tmp_dir!(), "toska_router_#{System.unique_integer([:positive])}"])

    File.mkdir_p!(tmp_dir)
    System.put_env("TOSKA_DATA_DIR", tmp_dir)
    System.delete_env("TOSKA_AUTH_TOKEN")
    System.delete_env("TOSKA_RATE_LIMIT_PER_SEC")
    System.delete_env("TOSKA_RATE_LIMIT_BURST")
    System.delete_env("TOSKA_REPLICA_URL")

    stop_store()
    start_store()
    Toska.RateLimiter.reset()

    on_exit(fn ->
      stop_store()

      case original_data_dir do
        nil -> System.delete_env("TOSKA_DATA_DIR")
        value -> System.put_env("TOSKA_DATA_DIR", value)
      end

      restore_env("TOSKA_AUTH_TOKEN", original_auth_token)
      restore_env("TOSKA_RATE_LIMIT_PER_SEC", original_rate_limit_per)
      restore_env("TOSKA_RATE_LIMIT_BURST", original_rate_limit_burst)
      restore_env("TOSKA_REPLICA_URL", original_replica_url)

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

  test "root endpoint returns html" do
    conn =
      conn("GET", "/")
      |> Toska.Router.call(@opts)

    assert conn.status == 200
    assert conn.resp_body =~ "Toska Server"
    assert get_resp_header(conn, "content-type") != []
  end

  test "root endpoint shows running status details" do
    port = TestHelpers.free_port()
    assert {:ok, _pid} = Toska.Server.start(host: "127.0.0.1", port: port, env: "test")

    assert :ok =
             TestHelpers.wait_until(fn ->
               Toska.Server.status().status == :running
             end, 1500)

    conn =
      conn("GET", "/")
      |> Toska.Router.call(@opts)

    assert conn.status == 200
    assert conn.resp_body =~ "Server Status: RUNNING"
    assert conn.resp_body =~ "Configuration:"

    :ok = Toska.Server.stop()
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

  test "stats returns metrics" do
    :ok = Toska.KVStore.put("stat", "ok")

    conn =
      conn("GET", "/stats")
      |> Toska.Router.call(@opts)

    assert conn.status == 200
    stats = Jason.decode!(conn.resp_body)
    assert stats["keys"] >= 1
    assert stats["aof_path"]
  end

  test "stats returns error when store is stopped" do
    stop_store()

    conn =
      conn("GET", "/stats")
      |> Toska.Router.call(@opts)

    assert conn.status == 503
  end

  test "put rejects non-string values" do
    conn =
      conn("PUT", "/kv/bad", Jason.encode!(%{value: 123}))
      |> put_req_header("content-type", "application/json")
      |> Toska.Router.call(@opts)

    assert conn.status == 400
    assert Jason.decode!(conn.resp_body)["error"] == "Value must be a string"
  end

  test "mget rejects non-list keys" do
    conn =
      conn("POST", "/kv/mget", Jason.encode!(%{keys: "nope"}))
      |> put_req_header("content-type", "application/json")
      |> Toska.Router.call(@opts)

    assert conn.status == 400
  end

  test "list keys honors prefix and limit" do
    :ok = Toska.KVStore.put("a1", "1")
    :ok = Toska.KVStore.put("a2", "2")
    :ok = Toska.KVStore.put("b1", "3")

    conn =
      conn("GET", "/kv/keys?prefix=a&limit=1")
      |> Toska.Router.call(@opts)

    assert conn.status == 200
    keys = Jason.decode!(conn.resp_body)["keys"]
    assert length(keys) == 1
    assert Enum.all?(keys, &String.starts_with?(&1, "a"))
  end

  test "replication aof rejects invalid offsets" do
    bad_conn =
      conn("GET", "/replication/aof?since=bad")
      |> Toska.Router.call(@opts)

    assert bad_conn.status == 400

    negative_conn =
      conn("GET", "/replication/aof?since=-1")
      |> Toska.Router.call(@opts)

    assert negative_conn.status == 400
  end

  test "replication aof returns 204 when offset exceeds size" do
    :ok = Toska.KVStore.put("offset", "ok")
    {:ok, aof_path} = Toska.KVStore.aof_path()
    size = File.stat!(aof_path).size

    conn =
      conn("GET", "/replication/aof?since=#{size + 1}&max_bytes=1024")
      |> Toska.Router.call(@opts)

    assert conn.status == 204
    assert get_resp_header(conn, "x-toska-aof-size") != []
  end

  test "replication aof defaults to offset 0 when since is missing" do
    :ok = Toska.KVStore.put("default_offset", "ok")

    conn =
      conn("GET", "/replication/aof?max_bytes=1024")
      |> Toska.Router.call(@opts)

    assert conn.status in [200, 204]
    assert get_resp_header(conn, "x-toska-aof-size") != []
  end

  test "replication aof returns error when store is stopped" do
    stop_store()

    conn =
      conn("GET", "/replication/aof?since=0")
      |> Toska.Router.call(@opts)

    assert conn.status == 503
    assert Jason.decode!(conn.resp_body)["error"] == "AOF unavailable"
  end

  test "health returns unhealthy when server is stopped" do
    conn =
      conn("GET", "/health")
      |> Toska.Router.call(@opts)

    assert conn.status == 503
    assert Jason.decode!(conn.resp_body)["status"] == "unhealthy"
  end

  test "status returns JSON" do
    conn =
      conn("GET", "/status")
      |> Toska.Router.call(@opts)

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["status"]
  end

  test "auth token enforces KV access" do
    System.put_env("TOSKA_AUTH_TOKEN", "secret")

    unauthorized_conn =
      conn("GET", "/kv/auth")
      |> Toska.Router.call(@opts)

    assert unauthorized_conn.status == 401

    authorized_conn =
      conn("GET", "/kv/auth")
      |> put_req_header("authorization", "Bearer secret")
      |> Toska.Router.call(@opts)

    assert authorized_conn.status in [200, 404]
  end

  test "auth token accepts x-toska-token header" do
    System.put_env("TOSKA_AUTH_TOKEN", "secret")

    conn =
      conn("GET", "/kv/auth-alt")
      |> put_req_header("x-toska-token", "secret")
      |> Toska.Router.call(@opts)

    assert conn.status in [200, 404]
  end

  test "rate limiter blocks after burst is exceeded" do
    System.put_env("TOSKA_RATE_LIMIT_PER_SEC", "1")
    System.put_env("TOSKA_RATE_LIMIT_BURST", "1")
    Toska.RateLimiter.reset()

    first_conn =
      conn("GET", "/kv/limit")
      |> Toska.Router.call(@opts)

    assert first_conn.status in [200, 404]

    second_conn =
      conn("GET", "/kv/limit")
      |> Toska.Router.call(@opts)

    assert second_conn.status == 429
  end

  test "follower mode blocks KV writes" do
    System.put_env("TOSKA_REPLICA_URL", "http://leader:4000")

    write_conn =
      conn("PUT", "/kv/readonly", Jason.encode!(%{value: "x"}))
      |> put_req_header("content-type", "application/json")
      |> Toska.Router.call(@opts)

    assert write_conn.status == 403

    read_conn =
      conn("GET", "/kv/readonly")
      |> Toska.Router.call(@opts)

    assert read_conn.status in [200, 404]
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

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

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
