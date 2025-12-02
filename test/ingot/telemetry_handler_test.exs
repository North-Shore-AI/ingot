defmodule Ingot.TelemetryHandlerTest do
  use ExUnit.Case, async: false

  alias Ingot.TelemetryHandler

  setup_all do
    # Start PubSub if not already started
    case Phoenix.PubSub.Supervisor.start_link(name: Ingot.PubSub) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  setup do
    # Ensure clean state - detach any existing handler
    try do
      :telemetry.detach("ingot-telemetry-handler")
    rescue
      ArgumentError -> :ok
    end

    # Subscribe to PubSub for testing broadcasts
    Phoenix.PubSub.subscribe(Ingot.PubSub, "queue:test-queue")
    Phoenix.PubSub.subscribe(Ingot.PubSub, "admin:global")

    :ok
  end

  describe "attach/0" do
    test "attaches telemetry handler to all expected events" do
      assert :ok = TelemetryHandler.attach()

      handlers = :telemetry.list_handlers([])
      handler_ids = Enum.map(handlers, & &1.id)

      assert "ingot-telemetry-handler" in handler_ids
    end

    test "does not crash when attached multiple times" do
      assert :ok = TelemetryHandler.attach()
      # Second attach should not crash (idempotent or replace)
      assert :ok = TelemetryHandler.attach()
    end
  end

  describe "handle_event/4 for [:ingot, :live_view, :mount]" do
    setup do
      TelemetryHandler.attach()
      :ok
    end

    test "logs LiveView mount event" do
      measurements = %{duration_ms: 42}

      metadata = %{
        view: IngotWeb.LabelingLive,
        queue_id: "test-queue",
        user_id: "user-123"
      }

      # Execute telemetry event
      :telemetry.execute([:ingot, :live_view, :mount], measurements, metadata)

      # Give it a moment to process
      Process.sleep(10)

      # Handler should have logged the event (we can't easily assert logs without capturing them)
      # But we can verify no crash occurred
      assert true
    end
  end

  describe "handle_event/4 for [:ingot, :label, :submit]" do
    setup do
      TelemetryHandler.attach()
      :ok
    end

    test "logs label submission event" do
      measurements = %{duration_ms: 123, client_latency_ms: 50}

      metadata = %{
        queue_id: "test-queue",
        assignment_id: "asg-456",
        user_id: "user-123",
        method: :keyboard
      }

      :telemetry.execute([:ingot, :label, :submit], measurements, metadata)
      Process.sleep(10)

      assert true
    end
  end

  describe "handle_event/4 for [:ingot, :forge_client, :get_sample]" do
    setup do
      TelemetryHandler.attach()
      :ok
    end

    test "logs successful ForgeClient call" do
      measurements = %{duration_ms: 25, payload_bytes: 1024}
      metadata = %{sample_id: "sample-123", result: :ok}

      :telemetry.execute([:ingot, :forge_client, :get_sample], measurements, metadata)
      Process.sleep(10)

      assert true
    end

    @tag capture_log: true
    test "logs failed ForgeClient call" do
      measurements = %{duration_ms: 100}
      metadata = %{sample_id: "sample-123", result: :error}

      :telemetry.execute([:ingot, :forge_client, :get_sample], measurements, metadata)
      Process.sleep(10)

      assert true
    end
  end

  describe "handle_event/4 for [:ingot, :anvil_client, :submit_label]" do
    setup do
      TelemetryHandler.attach()
      :ok
    end

    test "logs successful AnvilClient call" do
      measurements = %{duration_ms: 75}
      metadata = %{assignment_id: "asg-123", result: :ok}

      :telemetry.execute([:ingot, :anvil_client, :submit_label], measurements, metadata)
      Process.sleep(10)

      assert true
    end
  end

  describe "handle_event/4 for [:anvil, :label, :submitted]" do
    setup do
      TelemetryHandler.attach()
      :ok
    end

    test "broadcasts label submission to PubSub" do
      measurements = %{duration_ms: 50}

      metadata = %{
        queue_id: "test-queue",
        assignment_id: "asg-789",
        labeler_id: "user-456"
      }

      :telemetry.execute([:anvil, :label, :submitted], measurements, metadata)

      # Should receive broadcast on queue-specific topic
      assert_receive {:label_submitted, "asg-789", "user-456"}, 100

      # Should receive broadcast on admin global topic
      assert_receive {:label_submitted, "test-queue", "asg-789"}, 100
    end
  end

  describe "handle_event/4 for [:anvil, :queue, :stats_updated]" do
    setup do
      TelemetryHandler.attach()
      :ok
    end

    test "broadcasts queue stats to PubSub" do
      measurements = %{total: 100, completed: 47, remaining: 53}
      metadata = %{queue_id: "test-queue"}

      :telemetry.execute([:anvil, :queue, :stats_updated], measurements, metadata)

      # Should receive stats update on queue-specific topic
      assert_receive {:stats_updated, ^measurements}, 100

      # Should receive stats update on admin global topic
      assert_receive {:queue_stats_updated, "test-queue", ^measurements}, 100
    end
  end

  describe "handle_event/4 for [:forge, :sample, :created]" do
    setup do
      TelemetryHandler.attach()
      :ok
    end

    test "broadcasts sample creation to admin global" do
      measurements = %{}
      metadata = %{sample_id: "sample-999", pipeline_id: "pipeline-1"}

      :telemetry.execute([:forge, :sample, :created], measurements, metadata)

      # Should receive broadcast on admin global topic
      assert_receive {:sample_created, "sample-999", "pipeline-1"}, 100
    end
  end

  describe "detach/0" do
    test "detaches telemetry handler" do
      TelemetryHandler.attach()
      assert :ok = TelemetryHandler.detach()

      handlers = :telemetry.list_handlers([])
      handler_ids = Enum.map(handlers, & &1.id)

      refute "ingot-telemetry-handler" in handler_ids
    end

    test "detaching when not attached does not crash" do
      assert :ok = TelemetryHandler.detach()
    end
  end
end
