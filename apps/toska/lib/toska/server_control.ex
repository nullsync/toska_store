defmodule Toska.ServerControl do
  @moduledoc """
  Coordinate local and distributed control of the Toska server.
  """

  alias Toska.NodeControl
  alias Toska.Server

  @doc """
  Fetch server status, preferring the local node when available.
  """
  def status do
    local_status = Server.status()

    case local_status.status do
      :stopped ->
        case remote_call(:status, []) do
          {:ok, status} -> status
          _ -> local_status
        end

      _ ->
        local_status
    end
  end

  @doc """
  Stop the server on the local node or a connected node.
  """
  def stop(opts \\ []) do
    force = Keyword.get(opts, :force, false)

    case GenServer.whereis(Server) do
      nil ->
        case remote_call(:stop, [[force: force]]) do
          {:ok, :ok} -> :ok
          {:ok, result} -> result
          {:error, :no_runtime} -> {:error, :not_running}
          {:error, :unreachable} -> {:error, :not_running}
          {:error, reason} -> {:error, reason}
        end

      _pid ->
        Server.stop(force: force)
    end
  end

  defp remote_call(function, args) do
    with {:ok, node} <- NodeControl.connect() do
      case :rpc.call(node, Server, function, args) do
        {:badrpc, reason} -> {:error, reason}
        result -> {:ok, result}
      end
    end
  end
end
