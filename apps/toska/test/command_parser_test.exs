defmodule Toska.CommandParserTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  test "empty args show help" do
    output =
      capture_io(fn ->
        assert :ok = Toska.CommandParser.parse([])
      end)

    assert output =~ "Usage:"
  end

  test "unknown command returns error" do
    output =
      capture_io(fn ->
        assert {:error, :unknown_command} = Toska.CommandParser.parse(["nope"])
      end)

    assert output =~ "Unknown command"
  end

  test "status command runs" do
    output =
      capture_io(fn ->
        assert :ok = Toska.CommandParser.parse(["status"])
      end)

    assert output =~ "Toska Server Status"
  end

  test "start command help runs" do
    output =
      capture_io(fn ->
        assert :ok = Toska.CommandParser.parse(["start", "--help"])
      end)

    assert output =~ "Start the Toska server"
  end

  test "stop command help runs" do
    output =
      capture_io(fn ->
        assert :ok = Toska.CommandParser.parse(["stop", "--help"])
      end)

    assert output =~ "Stop the Toska server"
  end

  test "replicate command help runs" do
    output =
      capture_io(fn ->
        assert :ok = Toska.CommandParser.parse(["replicate", "--help"])
      end)

    assert output =~ "Start a replication follower"
  end

  test "config list runs with json output" do
    output =
      capture_io(fn ->
        assert :ok = Toska.CommandParser.parse(["config", "list", "--json"])
      end)

    decoded = Jason.decode!(output)
    assert Map.has_key?(decoded, "port")
  end
end
