defmodule Toska.Perf.Env do
  @moduledoc false

  def run(path) do
    data = %{
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      git: git_info(),
      elixir: %{
        version: System.version(),
        otp_release: System.otp_release()
      },
      erlang: to_string(:erlang.system_info(:version)),
      os: os_info(),
      cpu: cpu_info(),
      memory: memory_info(),
      hostname: hostname()
    }

    File.write!(path, Jason.encode!(data, pretty: true))
  end

  defp git_info do
    %{
      sha: cmd_output(["git", "rev-parse", "HEAD"]),
      branch: cmd_output(["git", "rev-parse", "--abbrev-ref", "HEAD"]),
      dirty: cmd_output(["git", "status", "--short"]) != ""
    }
  end

  defp os_info do
    {type, name} = :os.type()

    %{
      type: to_string(type),
      name: to_string(name),
      arch: to_string(:erlang.system_info(:system_architecture)),
      uname: cmd_output(["uname", "-a"])
    }
  end

  defp cpu_info do
    case File.read("/proc/cpuinfo") do
      {:ok, content} ->
        model =
          content
          |> String.split("\n")
          |> Enum.find_value(fn line ->
            if String.starts_with?(line, "model name") do
              case String.split(line, ":", parts: 2) do
                [_label, value] -> String.trim(value)
                _ -> nil
              end
            else
              nil
            end
          end)

        count =
          content
          |> String.split("\n")
          |> Enum.count(&String.starts_with?(&1, "processor"))

        %{
          model: model,
          cores: count
        }

      _ ->
        %{}
    end
  end

  defp memory_info do
    case File.read("/proc/meminfo") do
      {:ok, content} ->
        mem_total =
          content
          |> String.split("\n")
          |> Enum.find_value(fn line ->
            case String.split(line, ":", parts: 2) do
              ["MemTotal", value] -> String.trim(value)
              _ -> nil
            end
          end)

        %{
          mem_total: mem_total
        }

      _ ->
        %{}
    end
  end

  defp hostname do
    case :inet.gethostname() do
      {:ok, name} -> to_string(name)
      _ -> nil
    end
  end

  defp cmd_output([cmd | args]) do
    case System.cmd(cmd, args, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      _ -> ""
    end
  end
end

path =
  case System.argv() do
    [arg] -> arg
    _ ->
      System.get_env("PERF_ENV_PATH") ||
        case System.get_env("PERF_REPORT_DIR") do
          nil -> nil
          dir -> Path.join(dir, "env.json")
        end
  end

if is_binary(path) and path != "" do
  Toska.Perf.Env.run(path)
else
  raise "Usage: mix run scripts/perf/collect_env.exs -- <output_path>"
end
