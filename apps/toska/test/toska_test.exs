defmodule ToskaTest do
  use ExUnit.Case
  doctest Toska

  test "run function exists" do
    assert function_exported?(Toska, :run, 1)
  end
end
