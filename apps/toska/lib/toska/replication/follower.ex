defmodule Toska.Replication.Follower do
  @moduledoc """
  Simple follower that applies snapshots and tails the AOF stream.
  """

  use GenServer
  require Logger

  alias Toska.KVStore

  @default_poll_interval_ms 1000
  @default_http_timeout_ms 5000

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    leader_url = Keyword.get(opts, :leader_url)

    if is_binary(leader_url) and leader_url != "" do
      ensure_http()
      ensure_store()

      state = %{
        leader_url: String.trim_trailing(leader_url, "/"),
        poll_interval_ms: Keyword.get(opts, :poll_interval_ms, @default_poll_interval_ms),
        http_timeout_ms: Keyword.get(opts, :http_timeout_ms, @default_http_timeout_ms),
        offset: 0
      }

      {:ok, state, {:continue, :bootstrap}}
    else
      {:stop, :missing_leader_url}
    end
  end

  @impl true
  def handle_continue(:bootstrap, state) do
    case bootstrap(state) do
      {:ok, state} ->
        schedule_poll(state)
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("Replica bootstrap failed: #{inspect(reason)}")
        schedule_poll(state)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:poll, state) do
    state =
      case poll_aof(state) do
        {:ok, new_state} -> new_state
        {:error, reason} ->
          Logger.warning("Replica poll failed: #{inspect(reason)}")
          state
      end

    schedule_poll(state)
    {:noreply, state}
  end

  defp ensure_store do
    case GenServer.whereis(KVStore) do
      nil -> KVStore.start_link()
      _pid -> :ok
    end
  end

  defp bootstrap(state) do
    with {:ok, payload} <- fetch_snapshot(state),
         :ok <- KVStore.replace_snapshot(payload) do
      {:ok, %{state | offset: 0}}
    end
  end

  defp fetch_snapshot(state) do
    url = state.leader_url <> "/replication/snapshot"

    case http_get(url, state.http_timeout_ms) do
      {:ok, 200, _headers, body} ->
        case Jason.decode(body) do
          {:ok, payload} -> {:ok, payload}
          {:error, reason} -> {:error, reason}
        end

      {:ok, status, _headers, body} ->
        {:error, {:snapshot_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp poll_aof(state) do
    url = state.leader_url <> "/replication/aof?since=" <> Integer.to_string(state.offset)

    case http_get(url, state.http_timeout_ms) do
      {:ok, 204, headers, _body} ->
        {:ok, %{state | offset: parse_aof_size(headers, state.offset)}}

      {:ok, 200, headers, body} ->
        records = parse_aof_records(body)
        :ok = KVStore.apply_replication(records)
        {:ok, %{state | offset: parse_aof_size(headers, state.offset + byte_size(body))}}

      {:ok, status, _headers, body} ->
        {:error, {:aof_failed, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_aof_records(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case Jason.decode(line) do
        {:ok, record} -> [record]
        {:error, _} -> []
      end
    end)
  end

  defp parse_aof_size(headers, fallback) do
    case get_header(headers, "x-toska-aof-size") do
      nil -> fallback
      value ->
        case Integer.parse(value) do
          {int, ""} -> int
          _ -> fallback
        end
    end
  end

  defp get_header(headers, key) do
    key = String.downcase(key)

    headers
    |> Enum.find_value(fn {header, value} ->
      if String.downcase(to_string(header)) == key do
        to_string(value)
      end
    end)
  end

  defp http_get(url, timeout_ms) do
    request = {to_charlist(url), []}
    options = [timeout: timeout_ms, body_format: :binary]

    case :httpc.request(:get, request, [], options) do
      {:ok, {{_http_version, status, _reason}, headers, body}} ->
        {:ok, status, headers, body}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp schedule_poll(state) do
    Process.send_after(self(), :poll, state.poll_interval_ms)
  end

  defp ensure_http do
    :inets.start()
    :ssl.start()
    :ok
  end
end
