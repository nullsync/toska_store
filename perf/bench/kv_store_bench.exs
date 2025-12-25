defmodule Toska.Perf.KVStoreBench do
  @moduledoc false

  alias Toska.KVStore

  def run do
    report_dir = report_dir()
    File.mkdir_p!(report_dir)

    summary_path = Path.join(report_dir, "microbench_kv_store.json")
    raw_path = Path.join(report_dir, "microbench_kv_store_raw.json")

    original_data_dir = System.get_env("TOSKA_DATA_DIR")
    data_dir = Path.join(System.tmp_dir!(), "toska_perf_kv_#{System.unique_integer([:positive])}")

    File.mkdir_p!(data_dir)
    System.put_env("TOSKA_DATA_DIR", data_dir)

    dataset_size = parse_int(System.get_env("PERF_DATASET_SIZE"), 100_000)
    value_size = parse_int(System.get_env("PERF_VALUE_SIZE"), 128)
    mget_size = parse_int(System.get_env("PERF_MGET_SIZE"), 10)
    list_limit = parse_int(System.get_env("PERF_LIST_LIMIT"), 100)
    parallel = parse_int(System.get_env("PERF_PARALLEL"), 1)
    time = parse_float(System.get_env("PERF_TIME"), 5.0)
    warmup = parse_float(System.get_env("PERF_WARMUP"), 2.0)
    include_snapshot = parse_bool(System.get_env("PERF_INCLUDE_SNAPSHOT"), false)

    value = String.duplicate("x", value_size)

    try do
      start_store()

      keys = Enum.map(1..dataset_size, &"key_#{&1}")
      Enum.each(keys, &KVStore.put(&1, value))

      get_key = fn -> Enum.at(keys, :rand.uniform(dataset_size) - 1) end
      mget_keys = Enum.take(keys, mget_size)
      miss_key = "missing_#{dataset_size + 1}"

      benchmarks = %{
        "get_hit" => fn -> KVStore.get(get_key.()) end,
        "get_miss" => fn -> KVStore.get(miss_key) end,
        "put" => fn -> KVStore.put("bench_put_#{System.unique_integer([:positive])}", value) end,
        "mget_#{mget_size}" => fn -> KVStore.mget(mget_keys) end,
        "list_keys" => fn -> KVStore.list_keys("key_", list_limit) end
      }

      benchmarks =
        if include_snapshot do
          Map.merge(benchmarks, %{
            "snapshot" => fn -> KVStore.snapshot() end,
            "compact" => fn -> KVStore.compact() end
          })
        else
          benchmarks
        end

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
          parallel: parallel,
          percentiles: [50, 95, 99],
          formatters: formatters
        )

      summary = %{
        type: "microbench",
        name: "kv_store",
        generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        time_unit: "nanosecond",
        config: %{
          dataset_size: dataset_size,
          value_size: value_size,
          mget_size: mget_size,
          list_limit: list_limit,
          parallel: parallel,
          time_s: time,
          warmup_s: warmup,
          include_snapshot: include_snapshot
        },
        scenarios: scenario_stats(suite),
        raw_path: Path.basename(raw_path)
      }

      File.write!(summary_path, Jason.encode!(summary, pretty: true))
    after
      stop_store()
      restore_env("TOSKA_DATA_DIR", original_data_dir)
      File.rm_rf(data_dir)
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

  defp report_dir do
    System.get_env("PERF_REPORT_DIR") || Path.join([File.cwd!(), "perf", "reports", timestamp()])
  end

  defp timestamp do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_iso8601()
    |> String.replace(":", "-")
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

  defp parse_bool(nil, default), do: default
  defp parse_bool(value, _default) when value in ["1", "true", "TRUE", "yes", "YES"] do
    true
  end
  defp parse_bool(value, _default) when value in ["0", "false", "FALSE", "no", "NO"] do
    false
  end
  defp parse_bool(_, default), do: default
end

Toska.Perf.KVStoreBench.run()
