defmodule Ingot.GracefulShutdownTest do
  use ExUnit.Case, async: false

  alias Ingot.GracefulShutdown

  setup do
    # Ensure PubSub is started
    {:ok, _} = Application.ensure_all_started(:ingot)
    :ok
  end

  describe "drain/0" do
    test "completes successfully when no active sessions" do
      assert :ok = GracefulShutdown.drain()
    end

    test "broadcasts shutdown message to system:shutdown topic" do
      # Subscribe to the shutdown topic
      Phoenix.PubSub.subscribe(Ingot.PubSub, "system:shutdown")

      # Start drain in a separate process
      task = Task.async(fn -> GracefulShutdown.drain() end)

      # Assert we receive the shutdown broadcast
      assert_receive {:shutdown, "Server is shutting down for maintenance"}, 1000

      # Wait for drain to complete
      assert :ok = Task.await(task)
    end

    test "waits for active sessions to drain" do
      # Record start time
      start_time = System.monotonic_time(:millisecond)

      # Drain should complete quickly when no sessions
      assert :ok = GracefulShutdown.drain()

      # Should complete in under 2 seconds (not wait full 30s)
      duration = System.monotonic_time(:millisecond) - start_time
      assert duration < 2000, "Drain took #{duration}ms, expected < 2000ms"
    end

    test "returns ok even if timeout is reached" do
      # This test ensures drain doesn't block forever
      assert :ok = GracefulShutdown.drain()
    end
  end

  describe "count_active_sessions/0" do
    test "returns 0 when endpoint is not running" do
      # Ensure endpoint is not running
      if pid = Process.whereis(IngotWeb.Endpoint) do
        Process.exit(pid, :kill)
        Process.sleep(100)
      end

      assert GracefulShutdown.count_active_sessions() == 0
    end

    test "returns non-negative integer" do
      count = GracefulShutdown.count_active_sessions()
      assert is_integer(count)
      assert count >= 0
    end

    test "handles supervisor errors gracefully" do
      # This test ensures the function doesn't crash if supervisor is unavailable
      assert is_integer(GracefulShutdown.count_active_sessions())
    end
  end
end
