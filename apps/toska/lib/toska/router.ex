defmodule Toska.Router do
  @moduledoc """
  HTTP router for Toska server using Plug.

  Defines the HTTP endpoints and handles incoming requests.
  """

  use Plug.Router
  require Logger

  plug Plug.Logger
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
end
