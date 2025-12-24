defmodule Toska.Server do
  @moduledoc """
  Server management module for Toska.

  This module provides the foundation for server operations and will eventually
  become a full GenServer implementation for the Toska server process.
  """

  use GenServer
  require Logger

  alias Toska.NodeControl

  @name __MODULE__
  @http_server_name :"#{__MODULE__}.HTTPServer"

  # Client API

  @doc """
  Start the Toska server with the given options.
  """
  def start(opts \\ []) do
    host = Keyword.get(opts, :host, "localhost")
    port = Keyword.get(opts, :port, 4000)
    env = Keyword.get(opts, :env, "dev")
    daemon = Keyword.get(opts, :daemon, false)

    case GenServer.start_link(__MODULE__, %{
      host: host,
      port: port,
      env: env,
      daemon: daemon,
      started_at: System.system_time(:millisecond)
    }, name: @name) do
      {:ok, pid} ->
        Logger.info("Toska server started on #{host}:#{port} (env: #{env})")
        case NodeControl.ensure_server_node() do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning("Distributed control disabled: #{inspect(reason)}")
        end
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:error, {:already_started, pid}}

      {:error, reason} ->
        Logger.error("Failed to start Toska server: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stop the Toska server.
  """
  def stop(opts \\ []) do
    force = Keyword.get(opts, :force, false)

    case GenServer.whereis(@name) do
      nil ->
        {:error, :not_running}

      pid ->
        if force do
          Process.exit(pid, :kill)
          Logger.info("Toska server force stopped")
        else
          GenServer.stop(@name, :normal)
          Logger.info("Toska server stopped gracefully")
        end
        NodeControl.clear_runtime()
        :ok
    end
  end

  @doc """
  Get the current status of the Toska server.
  """
  def status do
    case GenServer.whereis(@name) do
      nil ->
        %{
          status: :stopped,
          uptime: nil,
          config: nil
        }

      _pid ->
        try do
          GenServer.call(@name, :get_status)
        catch
          :exit, {:noproc, _} ->
            %{
              status: :error,
              uptime: nil,
              config: nil
            }
        end
    end
  end

  @doc """
  Get server configuration.
  """
  def get_config do
    case GenServer.whereis(@name) do
      nil ->
        {:error, :not_running}

      _pid ->
        GenServer.call(@name, :get_config)
    end
  end

  @doc """
  Update server configuration.
  """
  def update_config(new_config) do
    case GenServer.whereis(@name) do
      nil ->
        {:error, :not_running}

      _pid ->
        GenServer.call(@name, {:update_config, new_config})
    end
  end

  # GenServer Callbacks

  @impl true
  def init(state) do
    Logger.info("Initializing Toska server with config: #{inspect(state)}")

    # Start the HTTP server using Bandit
    case start_http_server(state) do
      {:ok, bandit_pid} ->
        Logger.info("HTTP server started successfully on #{state.host}:#{state.port}")
        Process.send_after(self(), :server_ready, 500)
        {:ok, Map.merge(state, %{status: :starting, bandit_pid: bandit_pid})}

      {:error, reason} ->
        Logger.error("Failed to start HTTP server: #{inspect(reason)}")
        {:stop, {:http_server_failed, reason}}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    uptime = case state.started_at do
      nil -> nil
      started_at -> System.system_time(:millisecond) - started_at
    end

    status_info = %{
      status: state.status,
      uptime: uptime,
      config: Map.take(state, [:host, :port, :env, :daemon]),
      pid: inspect(self()),
      node: to_string(Node.self())
    }

    {:reply, status_info, state}
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    config = Map.take(state, [:host, :port, :env, :daemon])
    {:reply, {:ok, config}, state}
  end

  @impl true
  def handle_call({:update_config, new_config}, _from, state) do
    updated_state = Map.merge(state, new_config)
    Logger.info("Server configuration updated: #{inspect(new_config)}")
    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_info(:server_ready, state) do
    Logger.info("Toska server is ready and accepting connections")
    {:noreply, Map.put(state, :status, :running)}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Toska server terminating: #{inspect(reason)}")

    # Stop the HTTP server if it's running
    if Map.has_key?(state, :bandit_pid) and state.bandit_pid do
      stop_http_server()
    end

    NodeControl.clear_runtime()
    :ok
  end

  # Private helper functions

  defp start_http_server(state) do
    bandit_options = [
      plug: Toska.Router,
      port: state.port,
      ip: parse_host(state.host)
    ]

    case Bandit.start_link(bandit_options) do
      {:ok, pid} ->
        # Register the pid with our own name for management
        Process.register(pid, @http_server_name)
        {:ok, pid}
      {:error, {:already_started, pid}} ->
        {:ok, pid}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp stop_http_server do
    case Process.whereis(@http_server_name) do
      nil ->
        Logger.debug("HTTP server already stopped")
        :ok
      pid ->
        Process.unregister(@http_server_name)
        GenServer.stop(pid, :normal)
        Logger.info("HTTP server stopped")
        :ok
    end
  end

  defp parse_host("localhost"), do: {127, 0, 0, 1}
  defp parse_host("127.0.0.1"), do: {127, 0, 0, 1}
  defp parse_host("0.0.0.0"), do: {0, 0, 0, 0}
  defp parse_host(host) when is_binary(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} -> ip
      {:error, _} -> {127, 0, 0, 1}  # Default to localhost on parse error
    end
  end
  defp parse_host(_), do: {127, 0, 0, 1}
end
