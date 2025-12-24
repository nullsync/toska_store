defmodule Toska.Router do
  @moduledoc """
  HTTP router for Toska server using Plug.

  Defines the HTTP endpoints and handles incoming requests.
  """

  use Plug.Router
  require Logger

  alias Toska.ConfigManager
  alias Toska.RateLimiter

  plug Plug.Logger
  plug Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason
  plug :ensure_kv_access
  plug :match
  plug :dispatch

  # GET / - Welcome page showing server status
  get "/" do
    status = Toska.Server.status()

    response_body = """
    <!DOCTYPE html>
    <html>
    <head>
      <title>Toska Server</title>
      <style>
        body { font-family: Arial, sans-serif; margin: 40px; }
        .status { padding: 20px; border-radius: 5px; margin: 20px 0; }
        .running { background-color: #d4edda; border: 1px solid #c3e6cb; color: #155724; }
        .stopped { background-color: #f8d7da; border: 1px solid #f5c6cb; color: #721c24; }
        .error { background-color: #fff3cd; border: 1px solid #ffeaa7; color: #856404; }
        pre { background-color: #f8f9fa; padding: 15px; border-radius: 5px; overflow-x: auto; }
      </style>
    </head>
    <body>
      <h1>Toska Server</h1>
      <div class="status #{status_class(status.status)}">
        <h2>Server Status: #{String.upcase(to_string(status.status))}</h2>
        #{status_details(status)}
      </div>
      <h3>Available Endpoints:</h3>
      <ul>
        <li><a href="/">/</a> - This welcome page</li>
        <li><a href="/status">/status</a> - JSON status endpoint</li>
        <li><a href="/health">/health</a> - Health check endpoint</li>
        <li><a href="/stats">/stats</a> - KV store stats</li>
        <li>/kv/&lt;key&gt; - GET/PUT/DELETE key/value</li>
        <li>/kv/mget - POST body {"keys": ["a", "b"]}</li>
        <li><a href="/replication/info">/replication/info</a> - Replication metadata</li>
        <li><a href="/replication/status">/replication/status</a> - Follower status</li>
        <li><a href="/replication/snapshot">/replication/snapshot</a> - Snapshot file</li>
        <li>/replication/aof?since=0 - AOF stream</li>
      </ul>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, response_body)
  end

  # GET /status - JSON endpoint returning server status
  get "/status" do
    status = Toska.Server.status()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(status))
  end

  # GET /health - Health check endpoint
  get "/health" do
    status = Toska.Server.status()

    health_status = case status.status do
      :running -> "healthy"
      :starting -> "starting"
      _ -> "unhealthy"
    end

    response = %{
      status: health_status,
      timestamp: System.system_time(:millisecond),
      uptime: status.uptime
    }

    status_code = if health_status == "healthy", do: 200, else: 503

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status_code, Jason.encode!(response))
  end

  # GET /stats - KV store stats
  get "/stats" do
    case Toska.KVStore.stats() do
      {:ok, stats} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(stats))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(503, Jason.encode!(%{error: "KV store unavailable", reason: inspect(reason)}))
    end
  end

  # GET /replication/info - snapshot and AOF metadata
  get "/replication/info" do
    case Toska.KVStore.replication_info() do
      {:ok, info} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(info))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(503, Jason.encode!(%{error: "KV store unavailable", reason: inspect(reason)}))
    end
  end

  # GET /replication/status - follower status
  get "/replication/status" do
    case Toska.Replication.Follower.status() do
      {:ok, status} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(status))

      {:error, :not_running} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "Follower not running"}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(503, Jason.encode!(%{error: "Follower unavailable", reason: inspect(reason)}))
    end
  end

  # GET /replication/snapshot - snapshot file for followers
  get "/replication/snapshot" do
    case Toska.KVStore.snapshot() do
      :ok ->
        case {Toska.KVStore.snapshot_path(), Toska.KVStore.replication_info()} do
          {{:ok, path}, {:ok, info}} ->
            conn
            |> put_resp_content_type("application/json")
            |> put_replication_headers(info)
            |> send_file(200, path)

          {{:ok, path}, {:error, _reason}} ->
            conn
            |> put_resp_content_type("application/json")
            |> put_resp_header("x-toska-replication-warning", "info_unavailable")
            |> send_file(200, path)

          {_, {:error, reason}} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(503, Jason.encode!(%{error: "Snapshot unavailable", reason: inspect(reason)}))

          {{:error, reason}, _} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(503, Jason.encode!(%{error: "Snapshot unavailable", reason: inspect(reason)}))
        end

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(503, Jason.encode!(%{error: "Snapshot unavailable", reason: inspect(reason)}))
    end
  end

  # GET /replication/aof?since=offset&max_bytes=bytes - append-only log stream
  get "/replication/aof" do
    conn = fetch_query_params(conn)
    since_param = conn.params["since"]
    max_bytes_param = conn.params["max_bytes"]

    with {:ok, offset} <- parse_offset(since_param),
         {:ok, path} <- Toska.KVStore.aof_path() do
      size = file_size(path)
      max_bytes = parse_max_bytes(max_bytes_param)

      cond do
        offset < 0 ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(400, Jason.encode!(%{error: "Offset must be >= 0"}))

        offset >= size ->
          conn
          |> put_resp_content_type("application/octet-stream")
          |> put_resp_header("x-toska-aof-size", Integer.to_string(size))
          |> send_resp(204, "")

        true ->
          to_send = min(size - offset, max_bytes)
          conn
          |> put_resp_content_type("application/octet-stream")
          |> put_resp_header("x-toska-aof-size", Integer.to_string(size))
          |> put_resp_header("x-toska-aof-offset", Integer.to_string(offset))
          |> send_file(200, path, offset, to_send)
      end
    else
      {:error, :invalid_offset} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Invalid offset"}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(503, Jason.encode!(%{error: "AOF unavailable", reason: inspect(reason)}))
    end
  end

  # GET /kv/keys - list keys (optional prefix/limit)
  get "/kv/keys" do
    prefix = conn.params["prefix"] || ""
    limit = parse_int(conn.params["limit"], 100)

    case Toska.KVStore.list_keys(prefix, limit) do
      {:ok, keys} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{keys: keys}))

      {:error, :invalid_prefix} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Invalid prefix"}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(503, Jason.encode!(%{error: "KV store unavailable", reason: inspect(reason)}))
    end
  end

  # GET /kv/:key - fetch value
  get "/kv/:key" do
    case Toska.KVStore.get(key) do
      {:ok, value} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{key: key, value: value}))

      {:error, :not_found} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(404, Jason.encode!(%{error: "Not Found", key: key}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(503, Jason.encode!(%{error: "KV store unavailable", reason: inspect(reason)}))
    end
  end

  # PUT /kv/:key - set value with optional ttl_ms
  put "/kv/:key" do
    value = conn.body_params["value"]
    ttl_ms = conn.body_params["ttl_ms"]

    cond do
      not is_binary(value) ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Value must be a string"}))

      true ->
        case Toska.KVStore.put(key, value, ttl_ms) do
          :ok ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(%{ok: true, key: key}))

          {:error, reason} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(503, Jason.encode!(%{error: "KV store unavailable", reason: inspect(reason)}))
        end
    end
  end

  # DELETE /kv/:key - remove value
  delete "/kv/:key" do
    case Toska.KVStore.delete(key) do
      :ok ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{ok: true, key: key}))

      {:error, reason} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(503, Jason.encode!(%{error: "KV store unavailable", reason: inspect(reason)}))
    end
  end

  # POST /kv/mget - fetch multiple keys
  post "/kv/mget" do
    keys = conn.body_params["keys"]

    cond do
      not is_list(keys) ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Keys must be a list"}))

      true ->
        case Toska.KVStore.mget(keys) do
          {:ok, values} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(200, Jason.encode!(%{values: values}))

          {:error, reason} ->
            conn
            |> put_resp_content_type("application/json")
            |> send_resp(503, Jason.encode!(%{error: "KV store unavailable", reason: inspect(reason)}))
        end
    end
  end

  # Catch-all for undefined routes
  match _ do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{error: "Not Found", path: conn.request_path}))
  end

  # Private helper functions

  defp status_class(:running), do: "running"
  defp status_class(:stopped), do: "stopped"
  defp status_class(_), do: "error"

  defp status_details(%{status: :running, uptime: uptime, config: config}) when not is_nil(config) do
    """
    <p><strong>Uptime:</strong> #{format_uptime(uptime)}</p>
    <p><strong>Configuration:</strong></p>
    <pre>#{inspect(config, pretty: true)}</pre>
    """
  end

  defp status_details(%{status: :stopped}) do
    "<p>Server is currently stopped.</p>"
  end

  defp status_details(_) do
    "<p>Server status information unavailable.</p>"
  end

  defp format_uptime(nil), do: "N/A"
  defp format_uptime(uptime_ms) do
    seconds = div(uptime_ms, 1000)
    minutes = div(seconds, 60)
    hours = div(minutes, 60)

    cond do
      hours > 0 -> "#{hours}h #{rem(minutes, 60)}m #{rem(seconds, 60)}s"
      minutes > 0 -> "#{minutes}m #{rem(seconds, 60)}s"
      true -> "#{seconds}s"
    end
  end

  defp parse_offset(nil), do: {:ok, 0}
  defp parse_offset(offset) when is_integer(offset), do: {:ok, offset}
  defp parse_offset(offset) when is_binary(offset) do
    case Integer.parse(offset) do
      {value, ""} -> {:ok, value}
      _ -> {:error, :invalid_offset}
    end
  end

  defp parse_offset(_), do: {:error, :invalid_offset}

  defp parse_max_bytes(nil), do: 1024 * 1024
  defp parse_max_bytes(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> int
      _ -> 1024 * 1024
    end
  end

  defp parse_max_bytes(_), do: 1024 * 1024

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %File.Stat{size: size}} -> size
      _ -> 0
    end
  end

  defp put_replication_headers(conn, info) do
    conn
    |> maybe_put_header("x-toska-snapshot-checksum", Map.get(info, "snapshot_checksum") || Map.get(info, :snapshot_checksum))
    |> maybe_put_header("x-toska-snapshot-version", Map.get(info, "snapshot_version") || Map.get(info, :snapshot_version))
    |> maybe_put_header("x-toska-aof-version", Map.get(info, "aof_version") || Map.get(info, :aof_version))
  end

  defp maybe_put_header(conn, _key, nil), do: conn
  defp maybe_put_header(conn, key, value) do
    put_resp_header(conn, key, to_string(value))
  end

  defp ensure_kv_access(conn, _opts) do
    if kv_path?(conn.request_path) do
      conn
      |> ensure_auth()
      |> ensure_rate_limit()
      |> ensure_read_only()
    else
      conn
    end
  end

  defp ensure_auth(%Plug.Conn{halted: true} = conn), do: conn
  defp ensure_auth(conn) do
    token = auth_token()

    if token == "" do
      conn
    else
      header = get_req_header(conn, "authorization") |> List.first()
      alt_header = get_req_header(conn, "x-toska-token") |> List.first()

      if token_match?(token, header) or token_match?(token, alt_header) do
        conn
      else
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "Unauthorized"}))
        |> halt()
      end
    end
  end

  defp ensure_rate_limit(%Plug.Conn{halted: true} = conn), do: conn
  defp ensure_rate_limit(conn) do
    {per_sec, burst} = rate_limit_config()

    if RateLimiter.allowed?(client_key(conn), per_sec, burst) do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(429, Jason.encode!(%{error: "Rate limit exceeded"}))
      |> halt()
    end
  end

  defp ensure_read_only(%Plug.Conn{halted: true} = conn), do: conn
  defp ensure_read_only(conn) do
    if follower_mode?() and write_request?(conn) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(403, Jason.encode!(%{error: "Read-only follower"}))
      |> halt()
    else
      conn
    end
  end

  defp kv_path?(path) do
    String.starts_with?(path, "/kv") or path == "/stats"
  end

  defp write_request?(conn) do
    method = conn.method
    path = conn.request_path

    method in ["PUT", "DELETE"] and String.starts_with?(path, "/kv/")
  end

  defp follower_mode? do
    env = System.get_env("TOSKA_REPLICA_URL")

    if is_binary(env) and env != "" do
      true
    else
      case GenServer.whereis(ConfigManager) do
        nil -> false
        _pid ->
          case ConfigManager.list() do
            {:ok, config} ->
              url = config["replica_url"]
              is_binary(url) and url != ""

            _ ->
              false
          end
      end
    end
  end

  defp auth_token do
    env = System.get_env("TOSKA_AUTH_TOKEN")

    cond do
      is_binary(env) and env != "" ->
        env

      true ->
        case GenServer.whereis(ConfigManager) do
          nil -> ""
          _pid ->
            case ConfigManager.list() do
              {:ok, config} -> config["auth_token"] || ""
              _ -> ""
            end
        end
    end
  end

  defp token_match?(_token, nil), do: false
  defp token_match?(token, header) when is_binary(header) do
    header == token or header == "Bearer #{token}"
  end
  defp token_match?(_token, _header), do: false

  defp rate_limit_config do
    env_per = System.get_env("TOSKA_RATE_LIMIT_PER_SEC")
    env_burst = System.get_env("TOSKA_RATE_LIMIT_BURST")

    config =
      case GenServer.whereis(ConfigManager) do
        nil -> %{}
        _pid ->
          case ConfigManager.list() do
            {:ok, stored} -> stored
            _ -> %{}
          end
      end

    per_sec = parse_int(env_per, config["rate_limit_per_sec"], 0)
    burst = parse_int(env_burst, config["rate_limit_burst"], 0)

    {per_sec, burst}
  end

  defp parse_int(nil, nil, default), do: default
  defp parse_int(nil, value, default), do: parse_int(value, default)
  defp parse_int(value, _default, default), do: parse_int(value, default)

  defp parse_int(value, _default) when is_integer(value) and value >= 0, do: value
  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int >= 0 -> int
      _ -> default
    end
  end
  defp parse_int(_, default), do: default

  defp client_key(conn) do
    case conn.remote_ip do
      {_, _, _, _} = ip -> to_string(:inet.ntoa(ip))
      {_, _, _, _, _, _, _, _} = ip -> to_string(:inet.ntoa(ip))
      _ -> "unknown"
    end
  end
end
