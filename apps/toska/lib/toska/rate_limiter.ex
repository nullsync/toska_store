defmodule Toska.RateLimiter do
  @moduledoc """
  Simple ETS-backed token bucket rate limiter.
  """

  @table :toska_rate_limiter

  def allowed?(key, per_sec, burst) do
    cond do
      per_sec <= 0 or burst <= 0 ->
        true

      true ->
        ensure_table()
        now = System.monotonic_time(:millisecond)

        {tokens, last_ms} =
          case :ets.lookup(@table, key) do
            [{^key, stored_tokens, stored_last}] -> {stored_tokens, stored_last}
            _ -> {burst, now}
          end

        refreshed = min(burst, tokens + refill(tokens, now, last_ms, per_sec))

        if refreshed >= 1 do
          :ets.insert(@table, {key, refreshed - 1, now})
          true
        else
          :ets.insert(@table, {key, refreshed, now})
          false
        end
    end
  end

  def reset do
    if :ets.whereis(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :set, :public, read_concurrency: true, write_concurrency: true])

      _ ->
        :ok
    end
  end

  defp refill(_tokens, now, last_ms, per_sec) do
    elapsed_ms = max(now - last_ms, 0)
    per_sec * elapsed_ms / 1000
  end
end
