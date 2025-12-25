defmodule Toska.Perf.LeaderState do
  @moduledoc false

  use Agent

  def start_link do
    Agent.start_link(fn -> %{snapshot: %{}, aof: []} end, name: __MODULE__)
  end

  def set_snapshot(snapshot) when is_map(snapshot) do
    Agent.update(__MODULE__, &Map.put(&1, :snapshot, snapshot))
  end

  def set_aof(entries) when is_list(entries) do
    Agent.update(__MODULE__, &Map.put(&1, :aof, entries))
  end

  def snapshot do
    Agent.get(__MODULE__, & &1.snapshot)
  end

  def aof do
    Agent.get(__MODULE__, & &1.aof)
  end
end

defmodule Toska.Perf.LeaderPlug do
  @moduledoc false

  use Plug.Router

  plug :match
  plug :dispatch

  get "/replication/snapshot" do
    payload = Toska.Perf.LeaderState.snapshot()
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(payload))
  end

  get "/replication/aof" do
    body =
      Toska.Perf.LeaderState.aof()
      |> Enum.map(&Jason.encode!/1)
      |> Enum.join("\n")
      |> Kernel.<>("\n")

    conn
    |> put_resp_content_type("application/octet-stream")
    |> put_resp_header("x-toska-aof-size", Integer.to_string(byte_size(body)))
    |> send_resp(200, body)
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end

defmodule Toska.Perf.ReplicationBench do
  @moduledoc false

  alias Toska.KVStore
  alias Toska.Replication.Follower
  alias Toska.Perf.LeaderState

  def run do
    report_dir = report_dir()
    File.mkdir_p!(report_dir)

    summary_path = Path.join(report_dir, "microbench_replication.json")
    raw_path = Path.join(report_dir, "microbench_replication_raw.json")

    original_data_dir = System.get_env("TOSKA_DATA_DIR")
    data_dir = Path.join(System.tmp_dir!(), "toska_perf_replica_#{System.unique_integer([:positive])}")

    File.mkdir_p!(data_dir)
    System.put_env("TOSKA_DATA_DIR", data_dir)

    snapshot_keys = parse_int(System.get_env("PERF_REPLICA_SNAPSHOT_KEYS"), 1_000)
    aof_entries = parse_int(System.get_env("PERF_REPLICA_AOF_ENTRIES"), 100)
    poll_ms = parse_int(System.get_env("PERF_REPLICA_POLL_MS"), 50)
    timeout_ms = parse_int(System.get_env("PERF_REPLICA_TIMEOUT_MS"), 2000)
    wait_ms = parse_int(System.get_env("PERF_REPLICA_WAIT_MS"), max(timeout_ms * 2, 3000))
    time = parse_float(System.get_env("PERF_TIME"), 5.0)
    warmup = parse_float(System.get_env("PERF_WARMUP"), 2.0)

    bandit_pid = nil

    try do
      start_store()
      {:ok, _} = LeaderState.start_link()

      port = free_port()
      {:ok, pid} = Bandit.start_link(plug: Toska.Perf.LeaderPlug, port: port)
      bandit_pid = pid
      _ = bandit_pid
      leader_url = "http://localhost:#{port}"

      benchmarks = %{
        "bootstrap_and_tail" => fn ->
          run_iteration(leader_url, snapshot_keys, aof_entries, poll_ms, timeout_ms, wait_ms)
        end
      }

      formatters =
        if Code.ensure_loaded?(Benchee.Formatters.JSON) do
          [
            Benchee.Formatters.Console,
            {Benchee.Formatters.JSON, file: raw_path}
          ]
        else
          [Benchee.Formatters.Console]
        end

      suite =
        Benchee.run(
          benchmarks,
          time: time,
          warmup: warmup,
          parallel: 1,
          percentiles: [50, 95, 99],
          formatters: formatters
        )

      summary = %{
        type: "microbench",
        name: "replication",
        generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        time_unit: "nanosecond",
        config: %{
          snapshot_keys: snapshot_keys,
          aof_entries: aof_entries,
          poll_ms: poll_ms,
          timeout_ms: timeout_ms,
          wait_ms: wait_ms,
          time_s: time,
          warmup_s: warmup
        },
        scenarios: scenario_stats(suite),
        raw_path: Path.basename(raw_path)
      }

      File.write!(summary_path, Jason.encode!(summary, pretty: true))
    after
      stop_follower()
      stop_store()
      stop_bandit(bandit_pid)
      stop_leader_state()
      restore_env("TOSKA_DATA_DIR", original_data_dir)
      File.rm_rf(data_dir)
    end
  end

  defp run_iteration(leader_url, snapshot_keys, aof_entries, poll_ms, timeout_ms, wait_ms) do
    id = System.unique_integer([:positive])
    snapshot = %{"data" => snapshot_data(id, snapshot_keys)}
    aof = aof_data(id, aof_entries)

    LeaderState.set_snapshot(snapshot)
    LeaderState.set_aof(aof)

    offset_path = Path.join(System.get_env("TOSKA_DATA_DIR"), "replica.offset")
    File.rm(offset_path)

    stop_follower()

    {:ok, _pid} =
      Follower.start_link(
        leader_url: leader_url,
        poll_interval_ms: poll_ms,
        http_timeout_ms: timeout_ms
      )

    last_key = "aof_#{id}_#{aof_entries}"

    :ok = wait_until(fn -> match?({:ok, "1"}, KVStore.get(last_key)) end, wait_ms)

    stop_follower()
  end

  defp snapshot_data(id, count) do
    Enum.reduce(1..count, %{}, fn index, acc ->
      Map.put(acc, "snap_#{id}_#{index}", %{"value" => "1", "expires_at" => nil})
    end)
  end

  defp aof_data(id, count) do
    Enum.map(1..count, fn index ->
      %{"op" => "set", "key" => "aof_#{id}_#{index}", "value" => "1"}
    end)
  end

  defp wait_until(fun, timeout_ms) do
    start = System.monotonic_time(:millisecond)

    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) - start > timeout_ms do
        raise "Replication bench timed out after #{timeout_ms}ms"
      end

      Process.sleep(20)
      wait_until(fun, timeout_ms)
    end
  end

  defp scenario_stats(%{scenarios: scenarios}) when is_list(scenarios) do
    Enum.map(scenarios, fn scenario ->
      stats = scenario_stats_block(scenario)
      percentiles = stats.percentiles || %{}

      %{
        name: scenario.name,
        ips: Map.get(stats, :ips),
        average: Map.get(stats, :average),
        median: Map.get(stats, :median),
        p95: percentile(percentiles, 95),
        p99: percentile(percentiles, 99),
        std_dev: Map.get(stats, :std_dev)
      }
    end)
  end

  defp scenario_stats(_), do: []

  defp scenario_stats_block(scenario) do
    cond do
      Map.has_key?(scenario, :statistics) and scenario.statistics ->
        scenario.statistics

      Map.has_key?(scenario, :run_time_data) and scenario.run_time_data ->
        scenario.run_time_data.statistics || %{}

      true ->
        %{}
    end
  end

  defp percentile(map, key) do
    Map.get(map, key) || Map.get(map, key * 1.0)
  end

  defp start_store do
    case KVStore.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> raise "KV store failed to start: #{inspect(reason)}"
    end
  end

  defp stop_store do
    case GenServer.whereis(KVStore) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  defp stop_follower do
    case GenServer.whereis(Follower) do
      nil -> :ok
      pid ->
        try do
          GenServer.stop(pid)
        catch
          :exit, _ -> :ok
        end
    end
  end

  defp stop_leader_state do
    case Process.whereis(LeaderState) do
      nil -> :ok
      pid -> Agent.stop(pid)
    end
  end

  defp stop_bandit(pid) do
    if is_nil(pid) do
      :ok
    else
    try do
      GenServer.stop(pid)
    catch
      :exit, _ -> :ok
    end
    end
  end

  defp report_dir do
    System.get_env("PERF_REPORT_DIR") || Path.join([File.cwd!(), "perf", "reports", timestamp()])
  end

  defp timestamp do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_iso8601()
    |> String.replace(":", "-")
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  defp parse_int(nil, default), do: default
  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end
  defp parse_int(_, default), do: default

  defp parse_float(nil, default), do: default
  defp parse_float(value, default) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} when float > 0 -> float
      _ -> default
    end
  end
  defp parse_float(_, default), do: default

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, {_addr, port}} = :inet.sockname(socket)
    :gen_tcp.close(socket)
    port
  end
end

Toska.Perf.ReplicationBench.run()
