defmodule Toska.NodeControl do
  @moduledoc """
  Helpers for managing distributed node metadata for CLI control.
  """

  require Logger

  @runtime_file "toska_runtime.json"
  @server_node_name :toska
  @default_cookie :toska_cookie
  @runtime_atom_max_length 255
  @runtime_atom_pattern ~r/^[a-zA-Z0-9_.@-]+$/

  @doc """
  Ensure the server node is started for distributed control and publish metadata.
  """
  def ensure_server_node do
    with {:ok, node_name} <- ensure_node_started(@server_node_name),
         cookie <- ensure_cookie(),
         :ok <- write_runtime(node_name, cookie) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Connect to the running server node using the runtime metadata.
  """
  def connect do
    with {:ok, runtime} <- read_runtime(),
         {:ok, _} <- ensure_client_node(),
         :ok <- apply_cookie(runtime.cookie),
         {:ok, node} <- connect_to_node(runtime.node) do
      {:ok, node}
    end
  end

  @doc """
  Clear runtime metadata for the server node.
  """
  def clear_runtime do
    case File.rm(runtime_file_path()) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def runtime_file_path do
    Path.join(runtime_dir(), @runtime_file)
  end

  defp runtime_dir do
    Path.join([System.user_home(), ".toska"])
  end

  defp ensure_node_started(name) do
    if Node.alive?() do
      {:ok, Node.self()}
    else
      with :ok <- ensure_epmd() do
        case Node.start(name, :shortnames) do
          {:ok, _pid} ->
            {:ok, Node.self()}

          {:error, {:already_started, _pid}} ->
            {:ok, Node.self()}

          {:error, reason} ->
            Logger.warning("Failed to start distributed node: #{inspect(reason)}")
            {:error, reason}
        end
      end
    end
  end

  defp ensure_client_node do
    if Node.alive?() do
      {:ok, Node.self()}
    else
      name = :"toska_cli_#{System.unique_integer([:positive])}"

      with :ok <- ensure_epmd() do
        case Node.start(name, :shortnames) do
          {:ok, _pid} ->
            {:ok, Node.self()}

          {:error, reason} ->
            Logger.warning("Failed to start CLI node: #{inspect(reason)}")
            {:error, reason}
        end
      end
    end
  end

  defp ensure_cookie do
    cookie = Node.get_cookie()

    if cookie == :nocookie do
      Node.set_cookie(@default_cookie)
      @default_cookie
    else
      cookie
    end
  end

  defp apply_cookie(cookie) when is_binary(cookie) do
    case safe_to_atom(cookie) do
      {:ok, atom} -> apply_cookie(atom)
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_cookie(cookie) when is_atom(cookie) do
    Node.set_cookie(cookie)
    :ok
  end

  defp ensure_epmd do
    case System.find_executable("epmd") do
      nil ->
        {:error, :epmd_not_found}

      path ->
        case System.cmd(path, ["-daemon"]) do
          {_output, 0} -> :ok
          {output, status} -> {:error, {:epmd_start_failed, status, output}}
        end
    end
  end

  defp write_runtime(node_name, cookie) do
    File.mkdir_p!(runtime_dir())

    payload = %{
      "node" => Atom.to_string(node_name),
      "cookie" => Atom.to_string(cookie)
    }

    File.write(runtime_file_path(), Jason.encode!(payload, pretty: true))
  end

  defp read_runtime do
    case File.read(runtime_file_path()) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"node" => node, "cookie" => cookie}} ->
            if valid_runtime_value?(node) and valid_runtime_value?(cookie) do
              {:ok, %{node: node, cookie: cookie}}
            else
              {:error, :invalid_runtime}
            end

          {:ok, _} ->
            {:error, :invalid_runtime}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :enoent} ->
        {:error, :no_runtime}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp connect_to_node(node_name) when is_binary(node_name) do
    case safe_to_atom(node_name) do
      {:ok, atom} -> connect_to_node(atom)
      {:error, reason} -> {:error, reason}
    end
  end

  defp connect_to_node(node_name) when is_atom(node_name) do
    case Node.ping(node_name) do
      :pong -> {:ok, node_name}
      :pang -> {:error, :unreachable}
    end
  end

  defp safe_to_atom(value) when is_binary(value) do
    if valid_runtime_value?(value) do
      {:ok, String.to_atom(value)}
    else
      {:error, :invalid_runtime}
    end
  end

  defp valid_runtime_value?(value) when is_binary(value) do
    String.length(value) <= @runtime_atom_max_length and value =~ @runtime_atom_pattern
  end
end
