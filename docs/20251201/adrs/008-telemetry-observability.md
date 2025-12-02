# ADR-008: Telemetry & Observability

## Status
Accepted

## Context

Ingot operates as a thin UI layer over Forge and Anvil, relying on these services for all domain operations. Effective observability requires:

1. **Health Monitoring**: Real-time visibility into Forge/Anvil availability, response times, error rates
2. **User Activity Tracking**: Labeling velocity, time-per-sample, abandonment rates, keyboard shortcut usage
3. **Performance Metrics**: LiveView mount times, PubSub message latency, client round-trip times
4. **Error Surfacing**: Failed label submissions, timeout errors, validation failures visible to admins
5. **Distributed Tracing**: Propagate trace IDs from Ingot → Anvil → Forge for full request lineage
6. **Compliance Logging**: Audit trail for label submissions, queue modifications, exports (tied to ADR-006)

**Current State (v0.1):**
- Basic Phoenix telemetry (request duration, LiveView lifecycles)
- No integration with Forge/Anvil telemetry
- No structured error tracking
- No distributed tracing

**Integration Requirements:**

- **Forge Telemetry Events**: Sample creation, artifact upload, pipeline execution
  - `[:forge, :sample, :created]`
  - `[:forge, :pipeline, :executed]`
  - `[:forge, :artifact, :uploaded]`

- **Anvil Telemetry Events**: Label submission, assignment distribution, agreement calculation
  - `[:anvil, :label, :submitted]`
  - `[:anvil, :assignment, :completed]`
  - `[:anvil, :queue, :stats_updated]`

- **Foundation/AITrace**: NSAI standard tracing (trace_id, span_id, parent_span_id)
  - Propagate trace context in AnvilClient/ForgeClient calls
  - Emit spans for UI operations (mount, submit_label, fetch_assignment)

**Observability Personas:**

- **Labelers**: Need immediate feedback (label accepted, validation error)
- **Admins**: Need dashboard health indicators, error logs, performance charts
- **SREs**: Need metrics export (Prometheus), log aggregation (ELK/Loki), alerting (PagerDuty)
- **Researchers**: Need latency histograms, A/B test metrics (e.g., keyboard shortcuts vs mouse-only)

## Decision

**Subscribe to Forge and Anvil telemetry events via `:telemetry.attach_many/4`, convert to PubSub broadcasts for LiveView updates. Emit Ingot-specific telemetry for UI operations. Integrate with Foundation/AITrace for distributed tracing. Export metrics to Prometheus, logs to structured JSON (for ELK/Loki).**

### Architecture

```
┌────────────────────────────────────────────────┐
│      Forge / Anvil Applications                │
│  :telemetry.execute([...], measurements, meta) │
└────────────┬───────────────────────────────────┘
             │
             │ :telemetry.attach_many
             ▼
┌────────────────────────────────────────────────┐
│    Ingot.TelemetryHandler (Subscriber)         │
│  - Converts telemetry → PubSub (for LiveViews) │
│  - Logs structured events (JSON)               │
│  - Updates Prometheus metrics                  │
│  - Emits Foundation.Trace spans                │
└────────────┬───────────────────────────────────┘
             │
             ├──→ Phoenix.PubSub → LiveViews
             ├──→ Logger (JSON, ELK/Loki)
             ├──→ Prometheus.Registry
             └──→ Foundation.Trace (APM)

┌────────────────────────────────────────────────┐
│         Ingot UI Operations                    │
│  :telemetry.execute([...], measurements, meta) │
└────────────┬───────────────────────────────────┘
             │
             ▼
        Same pipeline
```

### Telemetry Events

#### Ingot Events (Emitted by Ingot)

```elixir
# LiveView mount
:telemetry.execute(
  [:ingot, :live_view, :mount],
  %{duration_ms: duration},
  %{view: LabelingLive, queue_id: queue_id, user_id: user_id}
)

# Label submission (client-side timing)
:telemetry.execute(
  [:ingot, :label, :submit],
  %{duration_ms: duration, client_latency_ms: client_latency},
  %{queue_id: queue_id, assignment_id: assignment_id, user_id: user_id, method: :keyboard}
)

# ForgeClient call
:telemetry.execute(
  [:ingot, :forge_client, :get_sample],
  %{duration_ms: duration, payload_bytes: payload_size},
  %{sample_id: sample_id, result: :ok}
)

# AnvilClient call
:telemetry.execute(
  [:ingot, :anvil_client, :submit_label],
  %{duration_ms: duration},
  %{assignment_id: assignment_id, result: :ok}
)

# Component rendering
:telemetry.execute(
  [:ingot, :component, :render_sample],
  %{duration_ms: duration},
  %{component: "CNS.IngotComponents", sample_id: sample_id}
)
```

#### Subscribed Events (From Forge/Anvil)

```elixir
# Forge events
[:forge, :sample, :created]
[:forge, :artifact, :uploaded]
[:forge, :pipeline, :executed]

# Anvil events
[:anvil, :label, :submitted]
[:anvil, :assignment, :completed]
[:anvil, :queue, :stats_updated]
[:anvil, :agreement, :calculated]
```

### Telemetry Handler Implementation

```elixir
defmodule Ingot.TelemetryHandler do
  require Logger

  @moduledoc """
  Centralized telemetry handler for Ingot.
  - Subscribes to Forge/Anvil events
  - Emits Prometheus metrics
  - Broadcasts to PubSub for LiveView updates
  - Logs structured events
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
      [:anvil, :assignment, :completed],
      [:anvil, :queue, :stats_updated]
    ]

    :telemetry.attach_many(
      "ingot-telemetry-handler",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:ingot, :live_view, :mount], measurements, metadata, _config) do
    # Emit Prometheus metric
    Prometheus.Histogram.observe(
      :ingot_live_view_mount_duration_seconds,
      [view: metadata.view],
      measurements.duration_ms / 1000
    )

    # Log structured event
    Logger.info("LiveView mounted",
      view: metadata.view,
      queue_id: metadata.queue_id,
      user_id: metadata.user_id,
      duration_ms: measurements.duration_ms
    )
  end

  def handle_event([:ingot, :label, :submit], measurements, metadata, _config) do
    # Prometheus counters and histograms
    Prometheus.Counter.inc(
      :ingot_labels_submitted_total,
      [queue_id: metadata.queue_id, method: metadata.method]
    )

    Prometheus.Histogram.observe(
      :ingot_label_submit_duration_seconds,
      [queue_id: metadata.queue_id],
      measurements.duration_ms / 1000
    )

    # Log
    Logger.info("Label submitted",
      queue_id: metadata.queue_id,
      assignment_id: metadata.assignment_id,
      user_id: metadata.user_id,
      duration_ms: measurements.duration_ms,
      method: metadata.method  # :keyboard, :mouse, :api
    )
  end

  def handle_event([:ingot, :forge_client, :get_sample], measurements, metadata, _config) do
    # Track client call performance
    Prometheus.Histogram.observe(
      :ingot_forge_client_duration_seconds,
      [operation: :get_sample, result: metadata.result],
      measurements.duration_ms / 1000
    )

    # Track errors
    if metadata.result == :error do
      Prometheus.Counter.inc(
        :ingot_forge_client_errors_total,
        [operation: :get_sample]
      )

      Logger.warning("ForgeClient error",
        operation: :get_sample,
        sample_id: metadata.sample_id,
        duration_ms: measurements.duration_ms
      )
    end
  end

  def handle_event([:anvil, :label, :submitted], measurements, metadata, _config) do
    # Broadcast to PubSub for real-time updates
    Phoenix.PubSub.broadcast(
      Ingot.PubSub,
      "queue:#{metadata.queue_id}",
      {:label_submitted, metadata.assignment_id, metadata.labeler_id}
    )

    Phoenix.PubSub.broadcast(
      Ingot.PubSub,
      "admin:global",
      {:label_submitted, metadata.queue_id, metadata.assignment_id}
    )

    # Log for audit trail
    Logger.info("Label submitted (Anvil)",
      queue_id: metadata.queue_id,
      assignment_id: metadata.assignment_id,
      labeler_id: metadata.labeler_id,
      duration_ms: measurements.duration_ms
    )
  end

  def handle_event([:anvil, :queue, :stats_updated], measurements, metadata, _config) do
    # Broadcast to admin dashboards
    Phoenix.PubSub.broadcast(
      Ingot.PubSub,
      "queue:#{metadata.queue_id}",
      {:stats_updated, measurements}
    )

    Phoenix.PubSub.broadcast(
      Ingot.PubSub,
      "admin:global",
      {:queue_stats_updated, metadata.queue_id, measurements}
    )
  end

  def handle_event([:forge, :sample, :created], _measurements, metadata, _config) do
    # Notify admin dashboards of new samples
    Phoenix.PubSub.broadcast(
      Ingot.PubSub,
      "admin:global",
      {:sample_created, metadata.sample_id, metadata.pipeline_id}
    )
  end
end
```

### Prometheus Metrics

```elixir
defmodule Ingot.PrometheusMet rics do
  use Prometheus.Metric

  def setup do
    # LiveView metrics
    Histogram.declare(
      name: :ingot_live_view_mount_duration_seconds,
      help: "Time to mount LiveView",
      labels: [:view],
      buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.0]
    )

    # Label submission metrics
    Counter.declare(
      name: :ingot_labels_submitted_total,
      help: "Total labels submitted",
      labels: [:queue_id, :method]
    )

    Histogram.declare(
      name: :ingot_label_submit_duration_seconds,
      help: "Time from submit button to next assignment",
      labels: [:queue_id],
      buckets: [0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0]
    )

    # Client call metrics
    Histogram.declare(
      name: :ingot_forge_client_duration_seconds,
      help: "ForgeClient call duration",
      labels: [:operation, :result],
      buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.0]
    )

    Histogram.declare(
      name: :ingot_anvil_client_duration_seconds,
      help: "AnvilClient call duration",
      labels: [:operation, :result],
      buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.0]
    )

    Counter.declare(
      name: :ingot_forge_client_errors_total,
      help: "ForgeClient errors",
      labels: [:operation]
    )

    Counter.declare(
      name: :ingot_anvil_client_errors_total,
      help: "AnvilClient errors",
      labels: [:operation]
    )

    # Component rendering metrics
    Histogram.declare(
      name: :ingot_component_render_duration_seconds,
      help: "Component render time",
      labels: [:component],
      buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.25, 0.5]
    )
  end
end
```

### Distributed Tracing (Foundation/AITrace)

```elixir
defmodule Ingot.Tracing do
  @moduledoc """
  Integration with Foundation.Trace for distributed tracing.
  """

  def start_span(name, metadata \\ %{}) do
    Foundation.Trace.start_span(
      name,
      Map.merge(metadata, %{service: "ingot"})
    )
  end

  def end_span(span) do
    Foundation.Trace.end_span(span)
  end

  def propagate_context do
    Foundation.Trace.get_context()
  end
end

# Usage in ForgeClient
defmodule Ingot.ForgeClient.ElixirAdapter do
  def get_sample(sample_id) do
    span = Ingot.Tracing.start_span("ingot.forge_client.get_sample", %{
      sample_id: sample_id
    })

    start_time = System.monotonic_time(:millisecond)

    result =
      case Forge.Samples.get(sample_id, trace_context: Ingot.Tracing.propagate_context()) do
        {:ok, sample} ->
          {:ok, to_sample_dto(sample)}

        {:error, reason} ->
          {:error, reason}
      end

    duration_ms = System.monotonic_time(:millisecond) - start_time

    :telemetry.execute(
      [:ingot, :forge_client, :get_sample],
      %{duration_ms: duration_ms},
      %{sample_id: sample_id, result: elem(result, 0)}
    )

    Ingot.Tracing.end_span(span)

    result
  end
end
```

### Error Surfacing (Admin Dashboard)

```elixir
defmodule IngotWeb.AdminDashboardLive do
  use IngotWeb, :live_view

  def mount(_params, _session, socket) do
    # Subscribe to error events
    Phoenix.PubSub.subscribe(Ingot.PubSub, "errors:global")

    {:ok, assign(socket, recent_errors: [])}
  end

  def handle_info({:error, error_details}, socket) do
    recent_errors = [error_details | Enum.take(socket.assigns.recent_errors, 49)]
    {:noreply, assign(socket, recent_errors: recent_errors)}
  end
end

# In TelemetryHandler, broadcast errors
def handle_event([:ingot, :anvil_client, :submit_label], measurements, metadata, _config) do
  if metadata.result == :error do
    Phoenix.PubSub.broadcast(
      Ingot.PubSub,
      "errors:global",
      {:error, %{
        type: :anvil_client_error,
        operation: :submit_label,
        assignment_id: metadata.assignment_id,
        reason: metadata.reason,
        timestamp: DateTime.utc_now()
      }}
    )
  end
end
```

### Structured Logging

```elixir
# config/prod.exs
config :logger, :console,
  format: {Jason, :encode!},  # JSON logging
  metadata: [:request_id, :user_id, :queue_id, :trace_id]

# Logger call
Logger.info("Label submitted",
  queue_id: queue_id,
  assignment_id: assignment_id,
  user_id: user_id,
  duration_ms: duration_ms,
  method: :keyboard,
  trace_id: trace_id
)

# Output:
# {"level":"info","message":"Label submitted","queue_id":"queue_123","assignment_id":"asg_456","user_id":"user_789","duration_ms":245,"method":"keyboard","trace_id":"abc-def-ghi","timestamp":"2025-12-01T10:30:45.123Z"}
```

### Health Checks

```elixir
defmodule IngotWeb.HealthController do
  use IngotWeb, :controller

  def index(conn, _params) do
    health = %{
      status: :ok,
      timestamp: DateTime.utc_now(),
      services: %{
        forge: check_forge(),
        anvil: check_anvil(),
        pubsub: check_pubsub()
      }
    }

    status_code = if all_healthy?(health.services), do: 200, else: 503

    conn
    |> put_status(status_code)
    |> json(health)
  end

  defp check_forge do
    case Ingot.ForgeClient.health_check() do
      {:ok, _} -> %{status: :healthy, latency_ms: 5}
      {:error, reason} -> %{status: :unhealthy, reason: reason}
    end
  end

  defp check_anvil do
    case Ingot.AnvilClient.health_check() do
      {:ok, _} -> %{status: :healthy, latency_ms: 3}
      {:error, reason} -> %{status: :unhealthy, reason: reason}
    end
  end

  defp check_pubsub do
    # Simple ping to PubSub
    %{status: :healthy}
  end

  defp all_healthy?(services) do
    Enum.all?(services, fn {_name, service} -> service.status == :healthy end)
  end
end

# router.ex
get "/health", HealthController, :index
```

### Dashboard Visualizations

**Latency Dashboard (Admin View):**

```heex
<!-- admin_dashboard_live.html.heex -->
<section class="metrics-section">
  <h2>Performance Metrics</h2>

  <div class="metrics-grid">
    <div class="metric-card">
      <h3>Avg Label Submit Time</h3>
      <span class="metric-value"><%= @metrics.avg_label_submit_ms %> ms</span>
      <canvas id="label-latency-chart" phx-hook="LatencyChart"></canvas>
    </div>

    <div class="metric-card">
      <h3>ForgeClient Latency</h3>
      <span class="metric-value"><%= @metrics.avg_forge_latency_ms %> ms</span>
      <div class="latency-histogram">
        <div class="bar" style={"height: #{@metrics.forge_p50}%"}>p50</div>
        <div class="bar" style={"height: #{@metrics.forge_p95}%"}>p95</div>
        <div class="bar" style={"height: #{@metrics.forge_p99}%"}>p99</div>
      </div>
    </div>

    <div class="metric-card">
      <h3>Error Rate</h3>
      <span class={"metric-value #{error_rate_class(@metrics.error_rate)}"}>
        <%= Float.round(@metrics.error_rate * 100, 2) %>%
      </span>
    </div>
  </div>
</section>
```

### Export to External Systems

**Prometheus Scrape Endpoint:**

```elixir
# router.ex
forward "/metrics", Prometheus.PlugExporter

# Prometheus scrapes http://ingot.nsai.io/metrics every 15s
```

**Log Aggregation (ELK/Loki):**

```yaml
# Filebeat config (ships logs to ELK)
filebeat.inputs:
  - type: log
    enabled: true
    paths:
      - /var/log/ingot/*.log
    json.keys_under_root: true
    json.add_error_key: true

output.elasticsearch:
  hosts: ["elasticsearch:9200"]
  index: "ingot-logs-%{+yyyy.MM.dd}"
```

## Consequences

### Positive

- **Comprehensive Visibility**: Single pane of glass for Ingot, Forge, and Anvil health. Admins see full stack status.

- **Root Cause Analysis**: Distributed tracing enables debugging slow label submissions (Ingot → Anvil → Forge sample fetch bottleneck).

- **Real-Time Feedback**: Telemetry → PubSub → LiveView pipeline provides instant UI updates (label submitted, error occurred).

- **Compliance**: Structured audit logs satisfy research reproducibility requirements (who labeled what, when, with what latency).

- **Proactive Alerting**: Prometheus metrics feed into AlertManager. SREs get paged if error rate > 5% or p95 latency > 2s.

### Negative

- **Telemetry Overhead**: Emitting events on every label submission adds microseconds. For high-throughput (1000s labels/sec), consider sampling.
  - *Mitigation*: Sample 10% of events for metrics, 100% for errors. Configurable via ENV var.

- **PubSub Fan-Out**: Broadcasting every label submission to "admin:global" topic can overwhelm if 100+ admins connected.
  - *Mitigation*: Throttle broadcasts (batch updates, send max 1/sec). Use Phoenix.Presence for efficient presence tracking.

- **Log Volume**: JSON logging every label submission generates GBs/day for large campaigns.
  - *Mitigation*: Log rotation (daily), retention policy (30 days), compress old logs. Use log sampling for high-volume queues.

- **Dependency on External Systems**: If Prometheus/ELK are down, metrics/logs are lost.
  - *Mitigation*: Local metrics buffer (ringbuffer, flush to disk). ELK downtime doesn't break Ingot, just delays log ingestion.

### Neutral

- **Metrics Granularity**: Per-queue metrics valuable but high cardinality (1000s queues → 1000s Prometheus series).
  - Trade-off: Aggregate to top-10 queues for dashboards. Keep per-queue metrics for detailed drill-down.

- **Trace Sampling**: Distributed tracing every request is expensive. Sample 1% in production, 100% in staging.
  - Foundation.Trace supports configurable sampling rates.

## Implementation Checklist

1. Implement `Ingot.TelemetryHandler` with event subscriptions
2. Define Prometheus metrics in `Ingot.PrometheusMetrics.setup/0`
3. Add telemetry calls to ForgeClient, AnvilClient operations
4. Add telemetry calls to LiveView mounts, label submissions
5. Integrate Foundation.Trace for distributed tracing
6. Add `/health` endpoint for service health checks
7. Configure structured JSON logging (production)
8. Add error broadcasting to PubSub for admin dashboard
9. Implement latency charts in admin dashboard (Chart.js)
10. Set up Prometheus scraping (add `/metrics` endpoint)
11. Configure log shipping (Filebeat/Fluentd → ELK/Loki)
12. Write runbook for common alerts (high error rate, slow latency)

## Monitoring Runbook (Summary)

**Alert: High Error Rate (>5%)**
- Check Ingot logs for error patterns (validation failures, timeouts)
- Check Forge/Anvil health (`/health` endpoint)
- Verify network connectivity (Ingot → Anvil)
- Roll back recent deployments if error rate spiked after deploy

**Alert: Slow Latency (p95 >2s)**
- Check Prometheus dashboard for bottleneck (Forge sample fetch? Anvil label write?)
- Check distributed traces for slow spans
- Scale Forge/Anvil if CPU/memory saturated
- Investigate slow database queries (Anvil Postgres)

**Alert: PubSub Lag**
- Check Phoenix.PubSub process mailbox sizes
- Reduce broadcast frequency (throttle updates)
- Scale Ingot horizontally (more web nodes)

## Related ADRs

- ADR-001: Stateless UI Architecture (telemetry emitted, not stored)
- ADR-002: Client Layer Design (client telemetry events)
- ADR-005: Realtime UX (telemetry → PubSub → LiveView)
- ADR-006: Admin Dashboard (error logs, latency charts)
