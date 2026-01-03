defmodule Toska.TestHelpers do
  @moduledoc false

  def tmp_dir(prefix) do
    Path.join([System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}"])
  end

  def free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, {_addr, port}} = :inet.sockname(socket)
    :gen_tcp.close(socket)
    port
  end

  def wait_until(fun, timeout_ms \\ 1000, interval_ms \\ 20) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait(fun, deadline, interval_ms)
  end

  def put_env(key, value) do
    case value do
      nil -> System.delete_env(key)
      _ -> System.put_env(key, value)
    end
  end

  def restore_env(key, value), do: put_env(key, value)

  def safe_stop_server do
    try do
      case Toska.Server.stop() do
        :ok -> :ok
        {:error, :not_running} -> :ok
        {:error, _reason} -> :ok
      end
    catch
      :exit, _ -> :ok
    end
  end

  defp do_wait(fun, deadline, interval_ms) do
    case fun.() do
      true ->
        :ok

      _ ->
        if System.monotonic_time(:millisecond) < deadline do
          :timer.sleep(interval_ms)
          do_wait(fun, deadline, interval_ms)
        else
          {:error, :timeout}
        end
    end
  end
end
