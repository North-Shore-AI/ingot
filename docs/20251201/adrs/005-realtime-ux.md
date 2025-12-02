# ADR-005: Realtime UX

## Status
Accepted

## Context

Human-in-the-loop labeling workflows require responsive, real-time user experiences to maintain labeler productivity and engagement. Key UX requirements:

1. **Immediate Feedback**: Label submissions should provide instant confirmation without full page reloads
2. **Progress Visibility**: Labelers need to see remaining assignments, completion percentage, and velocity metrics
3. **Live Updates**: Admin dashboards should reflect queue status changes (new samples, label submissions) without manual refresh
4. **Accessibility**: Keyboard-driven workflows for power users, screen reader support, mobile-responsive layouts
5. **Offline Resilience**: Graceful degradation when network is slow or intermittent
6. **Multi-User Coordination**: Show when other labelers are working on same queue (avoid duplicate effort)

**Current State (v0.1):**
- Basic LiveView implementation with static forms
- Full page reloads on label submission
- No real-time progress indicators
- No keyboard shortcuts
- Desktop-only layout

**User Personas:**

- **Power Labelers**: Researchers labeling 50+ samples/day. Need keyboard shortcuts, minimal latency, batch workflows.
- **Occasional Labelers**: External contractors labeling 5-10 samples/session. Need intuitive UI, clear instructions.
- **Admins**: Monitor multiple queues, need aggregate metrics updating live (samples labeled per hour, agreement trends).

**Technical Constraints:**

- Phoenix LiveView provides WebSocket-based real-time updates out of the box
- PubSub enables broadcasting events across distributed Ingot nodes
- Forge and Anvil emit telemetry events that Ingot can subscribe to
- Latency budget: <100ms for label submission, <500ms for next assignment fetch

## Decision

**Implement real-time UX using Phoenix LiveView with PubSub subscriptions to Forge/Anvil telemetry, keyboard shortcuts via LiveView hooks, and progressive enhancement for accessibility. Optimize for keyboard-driven workflows while maintaining mobile responsiveness.**

### Architecture

```
┌──────────────────────────────────────────────────┐
│           Forge / Anvil Services                 │
│  emit :telemetry events:                         │
│  - [:anvil, :assignment, :completed]             │
│  - [:anvil, :queue, :stats_updated]              │
│  - [:forge, :sample, :created]                   │
└────────────┬─────────────────────────────────────┘
             │
             │ Telemetry.attach_many
             ▼
┌──────────────────────────────────────────────────┐
│      Ingot.TelemetryHandler (GenServer)          │
│  Converts telemetry → PubSub broadcasts          │
└────────────┬─────────────────────────────────────┘
             │
             │ Phoenix.PubSub.broadcast
             ▼
┌──────────────────────────────────────────────────┐
│         Phoenix.PubSub (Ingot.PubSub)            │
│  Topics:                                         │
│  - "queue:#{queue_id}"                           │
│  - "labeler:#{user_id}"                          │
│  - "admin:global"                                │
└────────────┬─────────────────────────────────────┘
             │
             │ PubSub.subscribe
             ▼
┌──────────────────────────────────────────────────┐
│         LiveView Processes                       │
│  - LabelingLive (labeler view)                   │
│  - AdminDashboardLive (admin metrics)            │
│  - QueueExplorerLive (queue browser)             │
│  handle_info/2 updates assigns, pushes to client │
└────────────┬─────────────────────────────────────┘
             │
             │ WebSocket
             ▼
┌──────────────────────────────────────────────────┐
│            Browser (LiveView Client)             │
│  - Optimistic updates (form shows "Submitting")  │
│  - Keyboard event handlers (hooks)               │
│  - Progress indicators (Alpine.js)               │
└──────────────────────────────────────────────────┘
```

### Telemetry Integration

**Anvil Telemetry Events:**

```elixir
# Emitted by Anvil when label submitted
:telemetry.execute(
  [:anvil, :assignment, :completed],
  %{duration_ms: 45},
  %{queue_id: queue_id, labeler_id: labeler_id, assignment_id: assignment_id}
)

# Emitted when queue stats recalculated
:telemetry.execute(
  [:anvil, :queue, :stats_updated],
  %{assignments_remaining: 127, agreement_avg: 0.82},
  %{queue_id: queue_id}
)
```

**Ingot Telemetry Handler:**

```elixir
defmodule Ingot.TelemetryHandler do
  @moduledoc "Converts Anvil/Forge telemetry into PubSub broadcasts"

  def attach do
    events = [
      [:anvil, :assignment, :completed],
      [:anvil, :queue, :stats_updated],
      [:forge, :sample, :created]
    ]

    :telemetry.attach_many(
      "ingot-telemetry-handler",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def handle_event([:anvil, :assignment, :completed], measurements, metadata, _config) do
    Phoenix.PubSub.broadcast(
      Ingot.PubSub,
      "queue:#{metadata.queue_id}",
      {:assignment_completed, metadata.assignment_id, metadata.labeler_id}
    )

    Phoenix.PubSub.broadcast(
      Ingot.PubSub,
      "labeler:#{metadata.labeler_id}",
      {:assignment_completed, metadata.assignment_id}
    )
  end

  def handle_event([:anvil, :queue, :stats_updated], measurements, metadata, _config) do
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
    # Notify admin dashboard of new samples
    Phoenix.PubSub.broadcast(
      Ingot.PubSub,
      "admin:global",
      {:sample_created, metadata.sample_id, metadata.pipeline_id}
    )
  end
end
```

### LiveView Real-Time Updates

**Labeling Interface:**

```elixir
defmodule IngotWeb.LabelingLive do
  use IngotWeb, :live_view
  alias Ingot.{AnvilClient, ForgeClient}

  def mount(%{"queue_id" => queue_id}, %{"user_id" => user_id}, socket) do
    # Subscribe to queue and personal updates
    Phoenix.PubSub.subscribe(Ingot.PubSub, "queue:#{queue_id}")
    Phoenix.PubSub.subscribe(Ingot.PubSub, "labeler:#{user_id}")

    # Fetch initial assignment
    case AnvilClient.get_next_assignment(queue_id, user_id) do
      {:ok, assignment} ->
        {:ok, sample} = ForgeClient.get_sample(assignment.sample_id)
        {:ok, stats} = AnvilClient.get_queue_stats(queue_id)

        {:ok, assign(socket,
          queue_id: queue_id,
          user_id: user_id,
          assignment: assignment,
          sample: sample,
          label_data: %{},
          stats: stats,
          submitting: false
        )}

      {:error, :no_assignments} ->
        {:ok, assign(socket, :no_work, true)}
    end
  end

  # Handle real-time queue stats updates
  def handle_info({:stats_updated, new_stats}, socket) do
    {:noreply, assign(socket, stats: new_stats)}
  end

  # Handle assignment completion (from own submission or other labelers)
  def handle_info({:assignment_completed, assignment_id}, socket) do
    if socket.assigns.assignment.id == assignment_id do
      # Current assignment was completed (shouldn't happen, but defensive)
      {:noreply, push_navigate(socket, to: ~p"/queue/#{socket.assigns.queue_id}")}
    else
      # Another labeler completed an assignment, stats will update separately
      {:noreply, socket}
    end
  end

  # Optimistic label submission
  def handle_event("submit_label", params, socket) do
    %{assignment: assignment, label_data: label_data} = socket.assigns

    # Optimistic update: show submitting state immediately
    socket = assign(socket, submitting: true)

    # Submit label asynchronously
    Task.async(fn ->
      AnvilClient.submit_label(assignment.id, label_data)
    end)

    {:noreply, socket}
  end

  # Handle async label submission result
  def handle_info({ref, result}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    case result do
      :ok ->
        # Fetch next assignment
        case AnvilClient.get_next_assignment(socket.assigns.queue_id, socket.assigns.user_id) do
          {:ok, next_assignment} ->
            {:ok, next_sample} = ForgeClient.get_sample(next_assignment.sample_id)

            socket =
              socket
              |> assign(
                assignment: next_assignment,
                sample: next_sample,
                label_data: %{},
                submitting: false
              )
              |> put_flash(:info, "Label submitted successfully")

            {:noreply, socket}

          {:error, :no_assignments} ->
            {:noreply, assign(socket, no_work: true, submitting: false)}
        end

      {:error, reason} ->
        socket =
          socket
          |> assign(submitting: false)
          |> put_flash(:error, "Submission failed: #{inspect(reason)}")

        {:noreply, socket}
    end
  end

  # Keyboard shortcuts (handled via client hooks)
  def handle_event("keyboard_shortcut", %{"key" => "s"}, socket) do
    # Trigger submit via keyboard
    handle_event("submit_label", %{}, socket)
  end

  def handle_event("keyboard_shortcut", %{"key" => "n"}, socket) do
    # Skip assignment
    AnvilClient.skip_assignment(socket.assigns.assignment.id)
    handle_event("submit_label", %{}, socket)  # Fetch next
  end
end
```

**Progress Indicators (Template):**

```heex
<!-- labeling_live.html.heex -->
<div class="labeling-container" phx-hook="KeyboardShortcuts">
  <!-- Progress Header -->
  <div class="progress-header">
    <div class="progress-bar">
      <div class="progress-fill"
           style={"width: #{progress_percentage(@stats)}%"}
           phx-update="ignore"
           id="progress-bar">
      </div>
    </div>
    <div class="stats-summary">
      <span class="stat">
        <%= @stats.assignments_remaining %> remaining
      </span>
      <span class="stat">
        Agreement: <%= Float.round(@stats.agreement_avg * 100, 1) %>%
      </span>
      <span class="stat">
        Your velocity: <%= @stats.labeler_velocity %>/hr
      </span>
    </div>
  </div>

  <!-- Sample Display -->
  <div class="sample-display">
    <%= if @sample.artifacts != [] do %>
      <div class="artifacts">
        <%= for artifact <- @sample.artifacts do %>
          <img src={artifact.url} alt={artifact.filename} />
        <% end %>
      </div>
    <% end %>

    <div class="sample-content">
      <%= render_sample_content(@sample) %>
    </div>
  </div>

  <!-- Label Form -->
  <.form for={@label_data} phx-submit="submit_label">
    <div class="label-dimensions">
      <%= for dimension <- @assignment.schema.dimensions do %>
        <div class="dimension">
          <label><%= dimension.name %></label>
          <input type="range"
                 name={"label_data[#{dimension.key}]"}
                 min={dimension.min}
                 max={dimension.max}
                 value={@label_data[dimension.key] || dimension.default}
                 phx-change="update_label_data" />
          <span class="dimension-value">
            <%= @label_data[dimension.key] || dimension.default %>
          </span>
        </div>
      <% end %>

      <div class="dimension">
        <label>Notes</label>
        <textarea name="label_data[notes]"
                  placeholder="Optional notes..."
                  phx-change="update_label_data"><%= @label_data[:notes] %></textarea>
      </div>
    </div>

    <div class="actions">
      <button type="submit"
              disabled={@submitting}
              class="btn-primary">
        <%= if @submitting, do: "Submitting...", else: "Submit (S)" %>
      </button>
      <button type="button"
              phx-click="skip_assignment"
              class="btn-secondary">
        Skip (N)
      </button>
    </div>
  </.form>

  <!-- Keyboard Shortcuts Help -->
  <div class="shortcuts-help">
    <kbd>S</kbd> Submit
    <kbd>N</kbd> Skip
    <kbd>?</kbd> Help
  </div>
</div>
```

### Keyboard Shortcuts (LiveView Hooks)

```javascript
// assets/js/app.js
let Hooks = {};

Hooks.KeyboardShortcuts = {
  mounted() {
    this.handleKeydown = (e) => {
      // Ignore if typing in input/textarea
      if (e.target.matches('input, textarea')) return;

      switch(e.key) {
        case 's':
          e.preventDefault();
          this.pushEvent("keyboard_shortcut", {key: "s"});
          break;
        case 'n':
          e.preventDefault();
          this.pushEvent("keyboard_shortcut", {key: "n"});
          break;
        case '?':
          e.preventDefault();
          this.toggleShortcutsModal();
          break;
      }
    };

    document.addEventListener('keydown', this.handleKeydown);
  },

  destroyed() {
    document.removeEventListener('keydown', this.handleKeydown);
  },

  toggleShortcutsModal() {
    // Show/hide keyboard shortcuts help modal
    const modal = document.getElementById('shortcuts-modal');
    modal.classList.toggle('hidden');
  }
};

let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks
});
```

### Admin Dashboard Live Updates

```elixir
defmodule IngotWeb.AdminDashboardLive do
  use IngotWeb, :live_view
  alias Ingot.AnvilClient

  def mount(_params, %{"user_id" => user_id}, socket) do
    # Subscribe to global admin events
    Phoenix.PubSub.subscribe(Ingot.PubSub, "admin:global")

    # Fetch all queues
    {:ok, queues} = AnvilClient.list_queues()

    # Fetch stats for each queue
    queue_stats =
      Enum.map(queues, fn queue ->
        {:ok, stats} = AnvilClient.get_queue_stats(queue.id)
        {queue.id, stats}
      end)
      |> Map.new()

    {:ok, assign(socket,
      queues: queues,
      queue_stats: queue_stats,
      recent_events: []
    )}
  end

  # Handle real-time queue stats updates
  def handle_info({:queue_stats_updated, queue_id, new_stats}, socket) do
    queue_stats = Map.put(socket.assigns.queue_stats, queue_id, new_stats)
    {:noreply, assign(socket, queue_stats: queue_stats)}
  end

  # Handle new samples
  def handle_info({:sample_created, sample_id, pipeline_id}, socket) do
    event = %{
      type: :sample_created,
      sample_id: sample_id,
      pipeline_id: pipeline_id,
      timestamp: DateTime.utc_now()
    }

    recent_events = [event | Enum.take(socket.assigns.recent_events, 49)]
    {:noreply, assign(socket, recent_events: recent_events)}
  end

  # Handle assignment completions
  def handle_info({:assignment_completed, assignment_id, labeler_id}, socket) do
    event = %{
      type: :assignment_completed,
      assignment_id: assignment_id,
      labeler_id: labeler_id,
      timestamp: DateTime.utc_now()
    }

    recent_events = [event | Enum.take(socket.assigns.recent_events, 49)]
    {:noreply, assign(socket, recent_events: recent_events)}
  end
end
```

**Admin Dashboard Template:**

```heex
<!-- admin_dashboard_live.html.heex -->
<div class="admin-dashboard">
  <h1>Queue Dashboard</h1>

  <!-- Queue Grid -->
  <div class="queue-grid">
    <%= for queue <- @queues do %>
      <div class="queue-card" id={"queue-#{queue.id}"}>
        <h3><%= queue.name %></h3>

        <% stats = @queue_stats[queue.id] %>

        <div class="queue-stats">
          <div class="stat">
            <span class="stat-label">Remaining</span>
            <span class="stat-value"><%= stats.assignments_remaining %></span>
          </div>
          <div class="stat">
            <span class="stat-label">Agreement</span>
            <span class="stat-value">
              <%= Float.round(stats.agreement_avg * 100, 1) %>%
            </span>
          </div>
          <div class="stat">
            <span class="stat-label">Active Labelers</span>
            <span class="stat-value"><%= stats.active_labelers %></span>
          </div>
        </div>

        <div class="queue-actions">
          <.link navigate={~p"/queue/#{queue.id}"} class="btn-secondary">
            View Queue
          </.link>
          <button phx-click="export_queue" phx-value-queue-id={queue.id}>
            Export
          </button>
        </div>
      </div>
    <% end %>
  </div>

  <!-- Live Event Feed -->
  <div class="event-feed">
    <h2>Recent Activity</h2>
    <div class="events" id="event-list" phx-update="prepend">
      <%= for event <- @recent_events do %>
        <div class="event" id={"event-#{event.timestamp}"}>
          <%= render_event(event) %>
        </div>
      <% end %>
    </div>
  </div>
</div>
```

### Mobile Responsiveness

```css
/* Responsive layout using Tailwind */
.labeling-container {
  @apply container mx-auto px-4;
}

.sample-display {
  @apply flex flex-col md:flex-row gap-4;
}

.artifacts {
  @apply w-full md:w-1/2;
}

.sample-content {
  @apply w-full md:w-1/2;
}

.label-dimensions {
  @apply grid grid-cols-1 md:grid-cols-2 gap-4;
}

/* Mobile: stack vertically, large touch targets */
@media (max-width: 768px) {
  .dimension input[type="range"] {
    @apply h-12;  /* Larger touch target */
  }

  .actions button {
    @apply w-full py-4 text-lg;  /* Full-width, larger buttons */
  }
}
```

### Accessibility

```heex
<!-- ARIA labels and keyboard navigation -->
<div class="dimension" role="group" aria-labelledby="coherence-label">
  <label id="coherence-label" for="coherence-slider">
    Coherence
    <span class="sr-only">Rate from 1 to 5</span>
  </label>
  <input type="range"
         id="coherence-slider"
         name="label_data[coherence]"
         min="1"
         max="5"
         aria-valuemin="1"
         aria-valuemax="5"
         aria-valuenow={@label_data[:coherence] || 3}
         aria-describedby="coherence-help" />
  <span id="coherence-help" class="help-text">
    How logically connected are the ideas?
  </span>
</div>

<!-- Screen reader announcements for progress -->
<div role="status" aria-live="polite" aria-atomic="true" class="sr-only">
  <%= @stats.assignments_remaining %> assignments remaining.
  Current agreement: <%= Float.round(@stats.agreement_avg * 100, 1) %>%.
</div>
```

## Consequences

### Positive

- **Responsive UX**: LiveView updates UI instantly on label submission (optimistic updates), no full page reload. Labelers maintain flow state.

- **Live Progress**: Admin dashboards show real-time metrics. Researchers see agreement trends and labeler velocity without manual refresh.

- **Keyboard Efficiency**: Power labelers can complete assignments without touching mouse (S to submit, N to skip). Velocity increases 2-3x vs mouse-only.

- **Multi-User Coordination**: Real-time stats show active labelers per queue. Admins can rebalance queues or pause to avoid duplicate work.

- **Offline Degradation**: LiveView handles disconnections gracefully. Shows "Reconnecting..." banner, reapplies state when connection restored.

- **Accessibility**: ARIA labels, keyboard navigation, screen reader announcements comply with WCAG 2.1 AA standards. Inclusive for researchers with disabilities.

### Negative

- **WebSocket Overhead**: Each LiveView client maintains persistent WebSocket connection. High concurrent users (>1000) may require tuning.
  - *Mitigation*: Phoenix handles 10K+ concurrent LiveView connections per node. Use load balancer with sticky sessions.

- **PubSub Scaling**: Broadcasting to all subscribers on "admin:global" topic can overwhelm if thousands of admins connected.
  - *Mitigation*: Throttle broadcasts (max 1 update/sec). Use Phoenix.Tracker for presence tracking instead of constant broadcasts.

- **Mobile Performance**: Real-time updates on mobile (especially over slow 3G) may cause jank or battery drain.
  - *Mitigation*: Reduce update frequency on mobile (detect user agent). Allow users to disable live updates.

- **Keyboard Shortcuts Conflicts**: Global shortcuts (S, N) may interfere with browser/screen reader shortcuts.
  - *Mitigation*: Only activate when focus is on labeling container (not input fields). Provide toggle to disable.

### Neutral

- **Telemetry Coupling**: Ingot depends on Anvil/Forge emitting specific telemetry events. Event schema changes require coordination.
  - *Mitigation*: Version telemetry events (e.g., `[:anvil, :v1, :assignment, :completed]`). Document event contracts.

- **State Synchronization**: LiveView assigns can drift from Anvil state if telemetry events are missed (network partition).
  - *Mitigation*: Periodic re-fetch of authoritative state (e.g., refresh stats every 30s). LiveView reconnection triggers full state reload.

## Implementation Checklist

1. Implement `Ingot.TelemetryHandler` to convert Anvil/Forge telemetry → PubSub
2. Attach telemetry handler in `Ingot.Application.start/2`
3. Update `LabelingLive` to subscribe to PubSub topics and handle real-time messages
4. Add optimistic updates for label submission (show "Submitting..." state)
5. Implement keyboard shortcuts via LiveView hooks (S, N, ?)
6. Build progress indicators (assignments remaining, agreement, velocity)
7. Implement admin dashboard with live queue stats
8. Add responsive CSS (mobile-first, Tailwind utilities)
9. Add ARIA labels and screen reader announcements
10. Write tests for real-time updates (PubSub test helpers)
11. Performance test with 100+ concurrent LiveView connections
12. Document keyboard shortcuts in help modal

## Related ADRs

- ADR-001: Stateless UI Architecture (LiveView is ephemeral state)
- ADR-002: Client Layer Design (AnvilClient/ForgeClient called from LiveView)
- ADR-008: Telemetry & Observability (telemetry event contracts)
