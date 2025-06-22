defmodule Toska.ConfigManager do
  @moduledoc """
  Configuration manager for Toska.

  Handles reading, writing, and managing configuration for the Toska CLI and server.
  Configuration is stored in a simple key-value format and persisted to disk.
  """

  use GenServer
  require Logger

  @name __MODULE__
  @config_file "toska_config.json"
  @default_config %{
    "port" => 4000,
    "host" => "localhost",
    "env" => "dev",
    "log_level" => "info"
  }

  # Client API

  @doc """
  Start the ConfigManager GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @doc """
  Get a configuration value by key.
  """
  def get(key) when is_binary(key) do
    GenServer.call(@name, {:get, key})
  end

  def get(key) when is_atom(key) do
    get(Atom.to_string(key))
  end

  @doc """
  Set a configuration value.
  """
  def set(key, value) when is_binary(key) do
    GenServer.call(@name, {:set, key, value})
  end

  def set(key, value) when is_atom(key) do
    set(Atom.to_string(key), value)
  end

  @doc """
  List all configuration values.
  """
  def list do
    GenServer.call(@name, :list)
  end

  @doc """
  Reset a specific configuration key to its default value.
  """
  def reset(key) when is_binary(key) do
    GenServer.call(@name, {:reset, key})
  end

  def reset(key) when is_atom(key) do
    reset(Atom.to_string(key))
  end

  @doc """
  Reset all configuration to default values.
  """
  def reset_all do
    GenServer.call(@name, :reset_all)
  end

  @doc """
  Get the path to the configuration file.
  """
  def config_file_path do
    Path.join([System.user_home(), ".toska", @config_file])
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    config_path = config_file_path()
    config_dir = Path.dirname(config_path)

    # Ensure config directory exists
    File.mkdir_p!(config_dir)

    # Load existing config or create default
    config = load_config(config_path)

    Logger.info("ConfigManager started with config file: #{config_path}")

    {:ok, %{config: config, file_path: config_path}}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    case Map.get(state.config, key) do
      nil ->
        {:reply, {:error, :not_found}, state}

      value ->
        {:reply, {:ok, parse_value(value)}, state}
    end
  end

  @impl true
  def handle_call({:set, key, value}, _from, state) do
    # Validate the key and value
    case validate_config_pair(key, value) do
      {:ok, validated_value} ->
        new_config = Map.put(state.config, key, validated_value)
        new_state = %{state | config: new_config}

        case save_config(new_state.config, state.file_path) do
          :ok ->
            Logger.info("Configuration updated: #{key} = #{inspect(validated_value)}")
            {:reply, :ok, new_state}

          {:error, reason} ->
            Logger.error("Failed to save configuration: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    parsed_config = Enum.into(state.config, %{}, fn {k, v} -> {k, parse_value(v)} end)
    {:reply, {:ok, parsed_config}, state}
  end

  @impl true
  def handle_call({:reset, key}, _from, state) do
    case Map.get(@default_config, key) do
      nil ->
        {:reply, {:error, :unknown_key}, state}

      default_value ->
        new_config = Map.put(state.config, key, default_value)
        new_state = %{state | config: new_config}

        case save_config(new_state.config, state.file_path) do
          :ok ->
            Logger.info("Configuration key '#{key}' reset to default: #{inspect(default_value)}")
            {:reply, :ok, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call(:reset_all, _from, state) do
    new_state = %{state | config: @default_config}

    case save_config(new_state.config, state.file_path) do
      :ok ->
        Logger.info("All configuration reset to defaults")
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Private Functions

  defp load_config(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, config} ->
            # Merge with defaults to ensure all keys are present
            Map.merge(@default_config, config)

          {:error, reason} ->
            Logger.warning("Failed to parse config file, using defaults: #{inspect(reason)}")
            @default_config
        end

      {:error, :enoent} ->
        Logger.info("Config file not found, creating with defaults")
        save_config(@default_config, file_path)
        @default_config

      {:error, reason} ->
        Logger.warning("Failed to read config file, using defaults: #{inspect(reason)}")
        @default_config
    end
  end

  defp save_config(config, file_path) do
    case Jason.encode(config, pretty: true) do
      {:ok, json} ->
        File.write(file_path, json)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_config_pair(key, value) do
    case key do
      "port" ->
        validate_port(value)

      "host" ->
        validate_host(value)

      "env" ->
        validate_env(value)

      "log_level" ->
        validate_log_level(value)

      _ ->
        # Allow unknown keys for extensibility
        {:ok, value}
    end
  end

  defp validate_port(value) when is_integer(value) and value > 0 and value <= 65535 do
    {:ok, value}
  end

  defp validate_port(value) when is_binary(value) do
    case Integer.parse(value) do
      {port, ""} when port > 0 and port <= 65535 ->
        {:ok, port}

      _ ->
        {:error, "Port must be an integer between 1 and 65535"}
    end
  end

  defp validate_port(_), do: {:error, "Port must be an integer between 1 and 65535"}

  defp validate_host(value) when is_binary(value) and byte_size(value) > 0 do
    {:ok, value}
  end

  defp validate_host(_), do: {:error, "Host must be a non-empty string"}

  defp validate_env(value) when value in ["dev", "test", "prod"] do
    {:ok, value}
  end

  defp validate_env(_), do: {:error, "Environment must be one of: dev, test, prod"}

  defp validate_log_level(value) when value in ["debug", "info", "warn", "error"] do
    {:ok, value}
  end

  defp validate_log_level(_), do: {:error, "Log level must be one of: debug, info, warn, error"}

  defp parse_value(value) when is_binary(value) do
    # Try to parse as integer first
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> value
    end
  end

  defp parse_value(value), do: value
end
