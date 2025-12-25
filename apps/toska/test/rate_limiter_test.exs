defmodule Toska.RateLimiterTest do
  use ExUnit.Case, async: false

  setup do
    Toska.RateLimiter.init()
    Toska.RateLimiter.reset()
    :ok
  end

  test "allows when disabled" do
    assert Toska.RateLimiter.allowed?("client", 0, 0)
    assert Toska.RateLimiter.allowed?("client", -1, 0)
  end

  test "enforces burst and refills over time" do
    assert Toska.RateLimiter.allowed?("client", 1, 1)
    refute Toska.RateLimiter.allowed?("client", 1, 1)

    :timer.sleep(1100)
    assert Toska.RateLimiter.allowed?("client", 1, 1)
  end
end
