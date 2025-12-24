defmodule Toska.KVStoreTest do
  use ExUnit.Case, async: false

  setup do
    original_data_dir = System.get_env("TOSKA_DATA_DIR")
    tmp_dir = Path.join([System.tmp_dir!(), "toska_kv_#{System.unique_integer([:positive])}"])

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

  test "put and get return stored value" do
    assert :ok = Toska.KVStore.put("alpha", "1")
    assert {:ok, "1"} = Toska.KVStore.get("alpha")
  end

  test "ttl expires keys" do
    assert :ok = Toska.KVStore.put("temp", "value", 10)
    :timer.sleep(20)
    assert {:error, :not_found} = Toska.KVStore.get("temp")
  end

  test "aof replay restores values on restart" do
    assert :ok = Toska.KVStore.put("persist", "yes")
    stop_store()
    start_store()
    assert {:ok, "yes"} = Toska.KVStore.get("persist")
  end

  test "invalid snapshot checksum skips load" do
    stop_store()

    snapshot_path = Path.join(System.get_env("TOSKA_DATA_DIR"), "toska_snapshot.json")

    payload = %{
      "version" => 1,
      "created_at" => System.system_time(:millisecond),
      "checksum" => "bad",
      "data" => %{"ghost" => %{"value" => "1", "expires_at" => nil}}
    }

    File.write!(snapshot_path, Jason.encode!(payload))

    start_store()
    assert {:error, :not_found} = Toska.KVStore.get("ghost")
  end

  test "invalid AOF checksum is ignored" do
    stop_store()

    aof_path = Path.join(System.get_env("TOSKA_DATA_DIR"), "toska.aof")

    record = %{
      "v" => 1,
      "op" => "set",
      "key" => "bad",
      "value" => "1",
      "checksum" => "bad"
    }

    File.write!(aof_path, Jason.encode!(record) <> "\n")

    start_store()
    assert {:error, :not_found} = Toska.KVStore.get("bad")
  end

  test "apply_replication applies AOF records" do
    record = %{"v" => 1, "op" => "set", "key" => "rep", "value" => "ok"}
    record = Map.put(record, "checksum", checksum(record))

    assert :ok = Toska.KVStore.apply_replication([record])
    assert {:ok, "ok"} = Toska.KVStore.get("rep")
  end

  defp checksum(record) do
    record
    |> Enum.map(fn {key, value} -> [to_string(key), value] end)
    |> Enum.sort_by(&List.first/1)
    |> Jason.encode!()
    |> sha256()
  end

  defp sha256(data) do
    :crypto.hash(:sha256, data)
    |> Base.encode16(case: :lower)
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
