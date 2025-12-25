defmodule Toska.Perf.Report do
  @moduledoc false

  def run(dir) do
    env = load_json(Path.join(dir, "env.json"))
    kv = load_json(Path.join(dir, "microbench_kv_store.json"))
    repl = load_json(Path.join(dir, "microbench_replication.json"))
    k6_kv = load_json(Path.join(dir, "k6_kv_summary.json"))
    k6_kv_cfg = load_json(Path.join(dir, "k6_kv_config.json"))
    k6_repl = load_json(Path.join(dir, "k6_replication_summary.json"))
    k6_repl_cfg = load_json(Path.join(dir, "k6_replication_config.json"))

    lines = []
    lines = lines ++ ["# Toska performance report", ""]
    lines = lines ++ render_env(env)
    lines = lines ++ render_microbench("KVStore", kv)
    lines = lines ++ render_microbench("Replication", repl)
    lines = lines ++ render_k6("KV endpoints", k6_kv, k6_kv_cfg)
    lines = lines ++ render_k6("Replication endpoints", k6_repl, k6_repl_cfg)

    File.write!(Path.join(dir, "summary.md"), Enum.join(lines, "\n"))
  end

  defp render_env(nil), do: ["Generated: #{DateTime.utc_now() |> DateTime.to_iso8601()}", ""]
  defp render_env(env) do
    git = env["git"] || %{}
    elixir = env["elixir"] || %{}
    os = env["os"] || %{}
    cpu = env["cpu"] || %{}
    memory = env["memory"] || %{}

    dirty = if git["dirty"], do: "yes", else: "no"

    [
      "Generated: #{env["generated_at"]}",
      "Commit: #{git["sha"]} (dirty: #{dirty})",
      "Branch: #{git["branch"]}",
      "Elixir: #{elixir["version"]} (OTP #{elixir["otp_release"]})",
      "Erlang: #{env["erlang"]}",
      "OS: #{os["uname"]}",
      "CPU: #{cpu["model"]} (cores: #{cpu["cores"]})",
      "Memory: #{memory["mem_total"]}",
      "",
      ""
    ]
  end

  defp render_microbench(_title, nil), do: []
  defp render_microbench(title, data) do
    unit = data["time_unit"] || "microsecond"
    config = data["config"] || %{}
    scenarios = data["scenarios"] || []

    lines = ["## Microbench: #{title}", ""]

    if map_size(config) > 0 do
      config_line =
        config
        |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
        |> Enum.sort()
        |> Enum.join(", ")

      lines = lines ++ ["Config: #{config_line}", ""]
      lines = render_microbench_table(lines, scenarios, unit)
      lines ++ [""]
    else
      render_microbench_table(lines, scenarios, unit) ++ [""]
    end
  end

  defp render_microbench_table(lines, scenarios, unit) do
    header = "| Scenario | ips | avg (ms) | p50 (ms) | p95 (ms) | p99 (ms) |"
    divider = "|---|---|---|---|---|---|"

    rows =
      scenarios
      |> Enum.map(fn scenario ->
        avg = format_duration(scenario["average"], unit)
        median = format_duration(scenario["median"], unit)
        p95 = format_duration(scenario["p95"], unit)
        p99 = format_duration(scenario["p99"], unit)

        "| #{scenario["name"]} | #{format_float(scenario["ips"])} | #{avg} | #{median} | #{p95} | #{p99} |"
      end)

    lines ++ [header, divider] ++ rows
  end

  defp render_k6(_title, nil, _cfg), do: []
  defp render_k6(title, data, cfg) do
    metrics = data["metrics"] || %{}

    reqs = metric_value(metrics, "http_reqs", "rate")
    avg = metric_value(metrics, "http_req_duration", "avg")
    p50 = metric_value(metrics, "http_req_duration", "p(50)")
    p90 = metric_value(metrics, "http_req_duration", "p(90)")
    p99 = metric_value(metrics, "http_req_duration", "p(99)")
    failed =
      metric_value(metrics, "http_req_failed", "rate") ||
        metric_value(metrics, "http_req_failed", "value")

    lines = ["## Load: #{title}", ""]

    lines =
      if is_map(cfg) do
        config_line =
          cfg
          |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
          |> Enum.sort()
          |> Enum.join(", ")

        lines ++ ["Config: #{config_line}", ""]
      else
        lines
      end

    lines ++ [
      "- RPS: #{format_float(reqs)}",
      "- Latency avg (ms): #{format_float(avg)}",
      "- Latency p50 (ms): #{format_float(p50)}",
      "- Latency p90 (ms): #{format_float(p90)}",
      "- Latency p99 (ms): #{format_float(p99)}",
      "- Error rate: #{format_percent(failed)}",
      "",
      ""
    ]
  end

  defp metric_value(metrics, name, key) do
    case Map.get(metrics, name) do
      nil -> nil
      metric ->
        values = metric["values"] || metric
        values[key]
    end
  end

  defp format_duration(nil, _unit), do: "n/a"
  defp format_duration(value, unit) when is_number(value) do
    ms =
      case unit do
        "nanosecond" -> value / 1_000_000
        "microsecond" -> value / 1_000
        "millisecond" -> value * 1.0
        "second" -> value * 1_000
        _ -> value * 1.0
      end

    format_float(ms)
  end

  defp format_duration(_value, _unit), do: "n/a"

  defp format_float(nil), do: "n/a"
  defp format_float(value) when is_number(value) do
    :io_lib.format("~.2f", [value * 1.0])
    |> List.to_string()
  end
  defp format_float(_), do: "n/a"

  defp format_percent(nil), do: "n/a"
  defp format_percent(value) when is_number(value) do
    percent = value * 100.0

    :io_lib.format("~.2f%", [percent])
    |> List.to_string()
  end
  defp format_percent(_), do: "n/a"

  defp load_json(path) do
    case File.read(path) do
      {:ok, content} -> Jason.decode!(content)
      _ -> nil
    end
  end
end

dir =
  case System.argv() do
    [arg] -> arg
    _ -> System.get_env("PERF_REPORT_DIR")
  end

if is_binary(dir) and dir != "" do
  Toska.Perf.Report.run(dir)
else
  raise "Usage: mix run scripts/perf/gen_report.exs -- <report_dir>"
end
