defmodule Ingot.TelemetryHandler do
  @moduledoc """
  Centralized telemetry handler for Ingot.

  Subscribes to telemetry events from:
  - Ingot UI operations (LiveView mounts, label submissions)
  - ForgeClient and AnvilClient calls
  - Forge application events (sample creation, pipeline execution)
  - Anvil application events (label submission, queue stats)

  Responsibilities:
  - Broadcast events to PubSub for LiveView updates
  - Structured logging for audit trail
  - (Future) Emit Prometheus metrics
  - (Future) Distributed tracing integration
  """

  require Logger

  @handler_id "ingot-telemetry-handler"

  @doc """
  Attach telemetry handler to all Ingot, Forge, and Anvil events.

  This should be called during application startup (in Application.start/2).
  Idempotent - if already attached, detaches and reattaches.
  """
  def attach do
    events = [
      # Ingot events
      [:ingot, :live_view, :mount],
      [:ingot, :label, :submit],
      [:ingot, :forge_client, :get_sample],
      [:ingot, :anvil_client, :submit_label],

      # Forge events
      [:forge, :sample, :created],

      # Anvil events
      [:anvil, :label, :submitted],
      [:anvil, :queue, :stats_updated]
    ]

    # Detach if already attached (idempotent)
    detach()

    :telemetry.attach_many(
      @handler_id,
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  @doc """
  Detach the telemetry handler.

  Useful for cleanup in tests or graceful shutdown.
  Always returns :ok, even if handler is not attached.
  """
  def detach do
    case :telemetry.detach(@handler_id) do
      :ok -> :ok
      {:error, :not_found} -> :ok
    end
  end

  @doc """
  Handle telemetry events and route them appropriately.
  """
  def handle_event([:ingot, :live_view, :mount], measurements, metadata, _config) do
    Logger.info("LiveView mounted",
      view: inspect(metadata.view),
      queue_id: metadata[:queue_id],
      user_id: metadata[:user_id],
      duration_ms: measurements.duration_ms
    )
  end

  def handle_event([:ingot, :label, :submit], measurements, metadata, _config) do
    Logger.info("Label submitted",
      queue_id: metadata.queue_id,
      assignment_id: metadata.assignment_id,
      user_id: metadata.user_id,
      duration_ms: measurements.duration_ms,
      method: metadata.method
    )
  end

  def handle_event([:ingot, :forge_client, :get_sample], measurements, metadata, _config) do
    case metadata.result do
      :ok ->
        Logger.debug("ForgeClient.get_sample succeeded",
          sample_id: metadata.sample_id,
          duration_ms: measurements.duration_ms,
          payload_bytes: measurements[:payload_bytes]
        )

      :error ->
        Logger.warning("ForgeClient.get_sample failed",
          sample_id: metadata.sample_id,
          duration_ms: measurements.duration_ms
        )
    end
  end

  def handle_event([:ingot, :anvil_client, :submit_label], measurements, metadata, _config) do
    case metadata.result do
      :ok ->
        Logger.debug("AnvilClient.submit_label succeeded",
          assignment_id: metadata.assignment_id,
          duration_ms: measurements.duration_ms
        )

      :error ->
        Logger.warning("AnvilClient.submit_label failed",
          assignment_id: metadata.assignment_id,
          duration_ms: measurements.duration_ms
        )
    end
  end

  def handle_event([:anvil, :label, :submitted], measurements, metadata, _config) do
    # Broadcast to queue-specific topic for labelers in that queue
    Phoenix.PubSub.broadcast(
      Ingot.PubSub,
      "queue:#{metadata.queue_id}",
      {:label_submitted, metadata.assignment_id, metadata.labeler_id}
    )

    # Broadcast to admin global topic for dashboard updates
    Phoenix.PubSub.broadcast(
      Ingot.PubSub,
      "admin:global",
      {:label_submitted, metadata.queue_id, metadata.assignment_id}
    )

    Logger.info("Label submitted (Anvil)",
      queue_id: metadata.queue_id,
      assignment_id: metadata.assignment_id,
      labeler_id: metadata.labeler_id,
      duration_ms: measurements[:duration_ms]
    )
  end

  def handle_event([:anvil, :queue, :stats_updated], measurements, metadata, _config) do
    # Broadcast to queue-specific topic
    Phoenix.PubSub.broadcast(
      Ingot.PubSub,
      "queue:#{metadata.queue_id}",
      {:stats_updated, measurements}
    )

    # Broadcast to admin global topic
    Phoenix.PubSub.broadcast(
      Ingot.PubSub,
      "admin:global",
      {:queue_stats_updated, metadata.queue_id, measurements}
    )

    Logger.debug("Queue stats updated",
      queue_id: metadata.queue_id,
      stats: measurements
    )
  end

  def handle_event([:forge, :sample, :created], _measurements, metadata, _config) do
    # Notify admin dashboards of new samples
    Phoenix.PubSub.broadcast(
      Ingot.PubSub,
      "admin:global",
      {:sample_created, metadata.sample_id, metadata.pipeline_id}
    )

    Logger.info("Sample created (Forge)",
      sample_id: metadata.sample_id,
      pipeline_id: metadata[:pipeline_id]
    )
  end

  # Catch-all for any other events (should not happen, but defensive)
  def handle_event(event, measurements, metadata, _config) do
    Logger.debug("Unhandled telemetry event",
      event: event,
      measurements: measurements,
      metadata: metadata
    )
  end
end
