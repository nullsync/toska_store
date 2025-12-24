defmodule Toska.ConfigManagerTest do
  use ExUnit.Case, async: false

  setup do
    original_config_dir = System.get_env("TOSKA_CONFIG_DIR")
    tmp_dir = Path.join([System.tmp_dir!(), "toska_test_#{System.unique_integer([:positive])}"])
    was_started = app_started?(:toska)

    File.mkdir_p!(tmp_dir)
    System.put_env("TOSKA_CONFIG_DIR", tmp_dir)
    stop_app(:toska)
    stop_config_manager()
    start_config_manager()

    on_exit(fn ->
      stop_config_manager()

      case original_config_dir do
        nil -> System.delete_env("TOSKA_CONFIG_DIR")
        value -> System.put_env("TOSKA_CONFIG_DIR", value)
      end

      if was_started do
        Application.ensure_all_started(:toska)
      end

      File.rm_rf(tmp_dir)
    end)

    :ok
  end

  test "loads defaults when config is missing" do
    assert {:ok, config} = Toska.ConfigManager.list()
    assert config["port"] == 4000
    assert config["host"] == "localhost"
    assert config["env"] == "dev"
  end

  test "persists config changes to disk" do
    assert :ok = Toska.ConfigManager.set("port", 5050)
    assert {:ok, 5050} = Toska.ConfigManager.get("port")

    stop_config_manager()
    start_config_manager()
    assert {:ok, 5050} = Toska.ConfigManager.get("port")
  end

  test "reset restores defaults" do
    assert :ok = Toska.ConfigManager.set("host", "0.0.0.0")
    assert :ok = Toska.ConfigManager.reset("host")
    assert {:ok, "localhost"} = Toska.ConfigManager.get("host")
  end

  defp app_started?(app) do
    Enum.any?(Application.started_applications(), fn {name, _, _} -> name == app end)
  end

  defp stop_app(app) do
    if app_started?(app) do
      Application.stop(app)
    end

    :ok
  end

  defp stop_config_manager do
    case GenServer.whereis(Toska.ConfigManager) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  defp start_config_manager do
    child_spec = %{
      id: {:config_manager, System.unique_integer([:positive])},
      start: {Toska.ConfigManager, :start_link, [[]]},
      restart: :temporary
    }

    start_supervised!(child_spec)
  end
end
