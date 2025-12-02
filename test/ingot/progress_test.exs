defmodule Ingot.ProgressTest do
  use ExUnit.Case, async: false
  use Supertester.ExUnitFoundation

  alias Ingot.Progress

  setup do
    # Ensure PubSub is started
    {:ok, _} = Application.ensure_all_started(:ingot)
    :ok
  end

  describe "broadcast_label_completed/1" do
    test "broadcasts label completion event" do
      Progress.subscribe_labels()

      session_id = "session-123"
      Progress.broadcast_label_completed(session_id)

      assert_receive {:label_completed, ^session_id, %DateTime{}}
    end

    test "includes timestamp in broadcast" do
      Progress.subscribe_labels()

      Progress.broadcast_label_completed("session-456")

      assert_receive {:label_completed, "session-456", timestamp}
      assert %DateTime{} = timestamp
    end
  end

  describe "broadcast_user_joined/1" do
    test "broadcasts user joined event" do
      Progress.subscribe_users()

      user_id = "user-123"
      Progress.broadcast_user_joined(user_id)

      assert_receive {:user_joined, ^user_id, %DateTime{}}
    end

    test "includes timestamp in broadcast" do
      Progress.subscribe_users()

      Progress.broadcast_user_joined("user-456")

      assert_receive {:user_joined, "user-456", timestamp}
      assert %DateTime{} = timestamp
    end
  end

  describe "broadcast_user_left/1" do
    test "broadcasts user left event" do
      Progress.subscribe_users()

      user_id = "user-789"
      Progress.broadcast_user_left(user_id)

      assert_receive {:user_left, ^user_id, %DateTime{}}
    end

    test "includes timestamp in broadcast" do
      Progress.subscribe_users()

      Progress.broadcast_user_left("user-111")

      assert_receive {:user_left, "user-111", timestamp}
      assert %DateTime{} = timestamp
    end
  end

  describe "broadcast_queue_update/1" do
    test "broadcasts queue update event" do
      Progress.subscribe_queue()

      stats = %{total: 500, completed: 100, remaining: 400}
      Progress.broadcast_queue_update(stats)

      assert_receive {:queue_updated, ^stats, %DateTime{}}
    end

    test "includes timestamp in broadcast" do
      Progress.subscribe_queue()

      stats = %{total: 600, completed: 200, remaining: 400}
      Progress.broadcast_queue_update(stats)

      assert_receive {:queue_updated, ^stats, timestamp}
      assert %DateTime{} = timestamp
    end
  end

  describe "subscribe_labels/0" do
    test "subscribes to label completion events" do
      Progress.subscribe_labels()

      Progress.broadcast_label_completed("test-session")

      assert_receive {:label_completed, "test-session", _}
    end

    test "does not receive user events when only subscribed to labels" do
      Progress.subscribe_labels()

      Progress.broadcast_user_joined("test-user")

      refute_receive {:user_joined, _, _}, 100
    end
  end

  describe "subscribe_users/0" do
    test "subscribes to user join and leave events" do
      Progress.subscribe_users()

      Progress.broadcast_user_joined("user-1")
      Progress.broadcast_user_left("user-2")

      assert_receive {:user_joined, "user-1", _}
      assert_receive {:user_left, "user-2", _}
    end

    test "does not receive label events when only subscribed to users" do
      Progress.subscribe_users()

      Progress.broadcast_label_completed("test-session")

      refute_receive {:label_completed, _, _}, 100
    end
  end

  describe "subscribe_queue/0" do
    test "subscribes to queue update events" do
      Progress.subscribe_queue()

      stats = %{total: 300, completed: 50, remaining: 250}
      Progress.broadcast_queue_update(stats)

      assert_receive {:queue_updated, ^stats, _}
    end

    test "does not receive label events when only subscribed to queue" do
      Progress.subscribe_queue()

      Progress.broadcast_label_completed("test-session")

      refute_receive {:label_completed, _, _}, 100
    end
  end

  describe "subscribe_all/0" do
    test "subscribes to all progress events" do
      Progress.subscribe_all()

      # Broadcast all types of events
      Progress.broadcast_label_completed("session-1")
      Progress.broadcast_user_joined("user-1")
      Progress.broadcast_user_left("user-2")
      Progress.broadcast_queue_update(%{total: 100, completed: 10, remaining: 90})

      # Should receive all events
      assert_receive {:label_completed, "session-1", _}
      assert_receive {:user_joined, "user-1", _}
      assert_receive {:user_left, "user-2", _}
      assert_receive {:queue_updated, _, _}
    end
  end

  describe "multiple subscribers" do
    test "all subscribers receive broadcast" do
      # Subscribe from multiple processes
      parent = self()

      spawn(fn ->
        Progress.subscribe_labels()
        send(parent, :subscribed)

        receive do
          {:label_completed, session_id, _} -> send(parent, {:received, :p1, session_id})
        end
      end)

      spawn(fn ->
        Progress.subscribe_labels()
        send(parent, :subscribed)

        receive do
          {:label_completed, session_id, _} -> send(parent, {:received, :p2, session_id})
        end
      end)

      # Wait for both to subscribe
      assert_receive :subscribed
      assert_receive :subscribed

      # Broadcast event
      Progress.broadcast_label_completed("multi-session")

      # Both should receive it
      assert_receive {:received, :p1, "multi-session"}
      assert_receive {:received, :p2, "multi-session"}
    end
  end
end
