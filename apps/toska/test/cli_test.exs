defmodule Toska.CLITest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "main exits with 0 on success" do
    output =
      capture_io(fn ->
        Toska.CLI.main(["--help"], fn code -> send(self(), {:halt, code}) end)
      end)

    assert output =~ "Usage:"
    assert_receive {:halt, 0}
  end

  test "main exits with 1 on error" do
    output =
      capture_io(fn ->
        Toska.CLI.main(["nope"], fn code -> send(self(), {:halt, code}) end)
      end)

    assert output =~ "Unknown command"
    assert_receive {:halt, 1}
  end
end
