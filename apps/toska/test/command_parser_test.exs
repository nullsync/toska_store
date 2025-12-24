defmodule Toska.CommandParserTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  test "empty args show help" do
    output = capture_io(fn ->
      assert :ok = Toska.CommandParser.parse([])
    end)

    assert output =~ "Usage:"
  end

  test "unknown command returns error" do
    output = capture_io(fn ->
      assert {:error, :unknown_command} = Toska.CommandParser.parse(["nope"])
    end)

    assert output =~ "Unknown command"
  end
end
