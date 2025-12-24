defmodule Toska.BenchKV do
  @moduledoc false

  def run do
    :inets.start()
    :ssl.start()

    base_url = System.get_env("TOSKA_BENCH_URL") || "http://localhost:4000"
    total_ops = parse_int(System.get_env("TOSKA_BENCH_OPS"), 10_000)
    concurrency = parse_int(System.get_env("TOSKA_BENCH_CONCURRENCY"), 20)
    mode = System.get_env("TOSKA_BENCH_MODE") || "mixed"

    ops_per = max(div(total_ops, concurrency), 1)

    IO.puts("Benchmarking #{base_url} (ops=#{total_ops}, concurrency=#{concurrency}, mode=#{mode})")

    warmup(base_url)

    start_time = System.monotonic_time(:millisecond)

    1..concurrency
    |> Enum.map(fn worker ->
      Task.async(fn -> run_worker(base_url, ops_per, mode, worker) end)
    end)
    |> Enum.each(&Task.await(&1, :infinity))

    elapsed = System.monotonic_time(:millisecond) - start_time
    ops_done = ops_per * concurrency
    rate = Float.round(ops_done / max(elapsed, 1) * 1000, 2)

    IO.puts("Completed #{ops_done} ops in #{elapsed}ms (#{rate} ops/sec)")
  end

  defp warmup(base_url) do
    _ = request(:put, "#{base_url}/kv/bench_warm", %{"value" => "warm"})
    _ = request(:get, "#{base_url}/kv/bench_warm")
    :ok
  end

  defp run_worker(base_url, ops, mode, worker) do
    Enum.each(1..ops, fn i ->
      key = "bench_#{worker}_#{i}"

      case mode do
        "read" ->
          _ = request(:get, "#{base_url}/kv/#{key}")

        "write" ->
          _ = request(:put, "#{base_url}/kv/#{key}", %{"value" => "v"})

        _ ->
          _ = request(:put, "#{base_url}/kv/#{key}", %{"value" => "v"})
          _ = request(:get, "#{base_url}/kv/#{key}")
      end
    end)
  end

  defp request(:get, url) do
    :httpc.request(:get, {to_charlist(url), []}, [], [])
  end

  defp request(:put, url, body) do
    headers = [{'Content-Type', 'application/json'}]
    payload = Jason.encode!(body)
    :httpc.request(:put, {to_charlist(url), headers, 'application/json', payload}, [], [])
  end

  defp parse_int(nil, default), do: default
  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end
  defp parse_int(_, default), do: default
end

Toska.BenchKV.run()
