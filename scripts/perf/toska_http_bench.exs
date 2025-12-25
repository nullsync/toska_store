defmodule Toska.Perf.HttpBench do
  @moduledoc false

  def run(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args,
        strict: [
          host: :string,
          port: :integer,
          requests: :integer,
          concurrency: :integer,
          value_size: :integer,
          key_space: :integer,
          mode: :string,
          key_mode: :string,
          allow_miss: :boolean,
          output: :string,
          timeout_ms: :integer,
          connect_timeout_ms: :integer,
          key_prefix: :string
        ],
        aliases: [
          h: :host,
          p: :port,
          n: :requests,
          c: :concurrency
        ]
      )

    if invalid != [] do
      raise "Invalid options: #{inspect(invalid)}"
    end

    cfg = build_config(opts)
    :inets.start()
    :ssl.start()

    :httpc.set_options([
      max_sessions: cfg.concurrency * 2,
      max_keep_alive_length: 100,
      keep_alive_timeout: 5_000
    ])

    result = execute(cfg)
    output(result, cfg.output)
  end

  defp build_config(opts) do
    mode =
      case opts[:mode] || System.get_env("TOSKA_HTTP_BENCH_MODE") || "put" do
        "put" -> :put
        "get" -> :get
        other -> raise "Invalid mode: #{other} (use put|get)"
      end

    key_mode =
      case opts[:key_mode] || System.get_env("TOSKA_HTTP_BENCH_KEY_MODE") || "random" do
        "random" -> :random
        "sequential" -> :sequential
        other -> raise "Invalid key_mode: #{other} (use random|sequential)"
      end

    allow_miss =
      case opts[:allow_miss] do
        nil -> mode == :get
        value -> value
      end

    host = opts[:host] || System.get_env("TOSKA_HTTP_BENCH_HOST") || "127.0.0.1"
    port = opts[:port] || env_int("TOSKA_HTTP_BENCH_PORT") || 4000
    requests = opts[:requests] || env_int("TOSKA_HTTP_BENCH_REQUESTS") || 100_000
    concurrency = opts[:concurrency] || env_int("TOSKA_HTTP_BENCH_CONCURRENCY") || 50
    value_size = opts[:value_size] || env_int("TOSKA_HTTP_BENCH_VALUE_SIZE") || 128
    key_space = opts[:key_space] || env_int("TOSKA_HTTP_BENCH_KEY_SPACE") || 10_000
    timeout_ms = opts[:timeout_ms] || env_int("TOSKA_HTTP_BENCH_TIMEOUT_MS") || 5_000
    connect_timeout_ms =
      opts[:connect_timeout_ms] || env_int("TOSKA_HTTP_BENCH_CONNECT_TIMEOUT_MS") || 5_000

    key_prefix = opts[:key_prefix] || System.get_env("TOSKA_HTTP_BENCH_KEY_PREFIX") || "bench_"
    output = opts[:output] || System.get_env("TOSKA_HTTP_BENCH_OUTPUT")

    payload = "{\"value\":\"" <> String.duplicate("x", value_size) <> "\"}"

    %{
      mode: mode,
      key_mode: key_mode,
      allow_miss: allow_miss,
      host: host,
      port: port,
      requests: requests,
      concurrency: concurrency,
      value_size: value_size,
      key_space: key_space,
      timeout_ms: timeout_ms,
      connect_timeout_ms: connect_timeout_ms,
      key_prefix: key_prefix,
      payload: payload,
      output: output
    }
  end

  defp execute(cfg) do
    counts = worker_counts(cfg.requests, cfg.concurrency)
    {offsets, _} = Enum.map_reduce(counts, 0, fn count, acc -> {{count, acc}, acc + count} end)

    start_us = System.monotonic_time(:microsecond)

    results =
      Task.async_stream(
        offsets,
        fn {count, start_index} -> run_worker(count, start_index, cfg) end,
        max_concurrency: cfg.concurrency,
        timeout: :infinity
      )
      |> Enum.reduce(%{latencies: [], ok: 0, errors: 0}, fn
        {:ok, worker}, acc ->
          %{
            latencies: worker.latencies ++ acc.latencies,
            ok: acc.ok + worker.ok,
            errors: acc.errors + worker.errors
          }

        {:exit, reason}, _acc ->
          raise "Worker failed: #{inspect(reason)}"
      end)

    duration_s = (System.monotonic_time(:microsecond) - start_us) / 1_000_000
    total = results.ok + results.errors

    latencies = Enum.sort(results.latencies)
    avg_ms = ms(avg_us(latencies))

    %{
      mode: Atom.to_string(cfg.mode),
      host: cfg.host,
      port: cfg.port,
      requests: cfg.requests,
      concurrency: cfg.concurrency,
      value_size: cfg.value_size,
      key_space: cfg.key_space,
      duration_s: duration_s,
      ops_per_sec: if(duration_s > 0, do: total / duration_s, else: 0.0),
      avg_ms: avg_ms,
      p50_ms: ms(percentile(latencies, 50.0)),
      p90_ms: ms(percentile(latencies, 90.0)),
      p99_ms: ms(percentile(latencies, 99.0)),
      ok: results.ok,
      errors: results.errors
    }
  end

  defp worker_counts(total, concurrency) when concurrency > 0 do
    base = div(total, concurrency)
    extra = rem(total, concurrency)

    Enum.map(0..(concurrency - 1), fn idx ->
      if idx < extra, do: base + 1, else: base
    end)
  end

  defp run_worker(count, start_index, cfg) do
    :rand.seed(:exsplus, {System.unique_integer([:positive]), start_index, count})
    do_run(count, start_index, cfg, [], 0, 0)
  end

  defp do_run(0, _start_index, _cfg, latencies, ok, errors) do
    %{latencies: latencies, ok: ok, errors: errors}
  end

  defp do_run(n, start_index, cfg, latencies, ok, errors) do
    idx = n - 1
    key = build_key(cfg, start_index + idx)
    {status, elapsed_us} = request(cfg, key)

    {ok, errors} =
      if ok_status?(status, cfg) do
        {ok + 1, errors}
      else
        {ok, errors + 1}
      end

    do_run(n - 1, start_index, cfg, [elapsed_us | latencies], ok, errors)
  end

  defp build_key(%{key_mode: :sequential, key_prefix: prefix}, index) do
    prefix <> Integer.to_string(index)
  end

  defp build_key(%{key_mode: :random, key_prefix: prefix, key_space: key_space}, _index) do
    value = :rand.uniform(key_space) - 1
    prefix <> Integer.to_string(value)
  end

  defp request(cfg, key) do
    url = "http://#{cfg.host}:#{cfg.port}/kv/#{key}"
    url_charlist = String.to_charlist(url)
    headers = [{~c"content-type", ~c"application/json"}]
    http_opts = [timeout: cfg.timeout_ms, connect_timeout: cfg.connect_timeout_ms]

    {elapsed_us, result} =
      :timer.tc(fn ->
        case cfg.mode do
          :put ->
            :httpc.request(:put, {url_charlist, headers, ~c"application/json", cfg.payload}, http_opts, [])

          :get ->
            :httpc.request(:get, {url_charlist, headers}, http_opts, [])
        end
      end)

    status =
      case result do
        {:ok, {{_version, code, _reason}, _headers, _body}} -> code
        {:error, _} -> :error
      end

    {status, elapsed_us}
  end

  defp ok_status?(:error, _cfg), do: false
  defp ok_status?(code, %{mode: :put}) when is_integer(code), do: code == 200

  defp ok_status?(code, %{mode: :get, allow_miss: allow_miss}) when is_integer(code) do
    if allow_miss do
      code in [200, 404]
    else
      code == 200
    end
  end

  defp avg_us([]), do: 0
  defp avg_us(latencies), do: Enum.sum(latencies) / length(latencies)

  defp percentile([], _p), do: 0
  defp percentile(latencies, p) do
    count = length(latencies)
    rank = Float.ceil(p / 100 * count) |> trunc()
    idx = max(rank - 1, 0)
    Enum.at(latencies, idx)
  end

  defp ms(nil), do: 0.0
  defp ms(value), do: value / 1000

  defp output(result, nil) do
    IO.puts(Jason.encode!(result, pretty: true))
  end

  defp output(result, path) do
    File.write!(path, Jason.encode!(result, pretty: true))
  end

  defp env_int(name) do
    case System.get_env(name) do
      nil -> nil
      value -> String.to_integer(value)
    end
  end
end

Toska.Perf.HttpBench.run(System.argv())
