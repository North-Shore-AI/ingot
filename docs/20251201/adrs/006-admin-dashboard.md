# ADR-006: Admin Dashboard

## Status
Accepted

## Context

Researchers and ML engineers managing human labeling workflows need comprehensive administrative capabilities beyond what labelers require. Admin responsibilities include:

1. **Queue Management**: Create/configure queues, set labeling policies (redundancy levels, expertise weighting), pause/resume assignment distribution
2. **Quality Monitoring**: Track inter-labeler agreement, identify outlier labelers, detect systematic biases
3. **Label Review**: Inspect individual labels, view disagreements, perform adjudication on flagged samples
4. **Data Export**: Trigger exports to various formats (JSONL, CSV, Parquet), download manifests for Crucible integration
5. **Audit & Compliance**: View complete audit trail (who labeled what when), track policy changes, export for compliance

**Current State (v0.1):**
- No admin UI (queue configuration done via IEx console)
- No visibility into labeler performance or agreement metrics
- No structured adjudication workflow
- Manual export via Anvil API calls

**User Workflows:**

- **Queue Setup**: Admin creates queue in Anvil, links to Forge pipeline, defines label schema (dimensions, validation rules), sets policy (3x redundancy, random assignment)
- **Monitoring**: During labeling campaign, admin monitors progress (100/500 samples labeled), agreement per dimension (coherence: 85%, groundedness: 72%), labeler velocity
- **Quality Control**: If agreement drops below threshold, admin inspects disagreements, identifies problematic samples, flags for adjudication
- **Adjudication**: Expert reviews flagged samples, sees all conflicting labels side-by-side, submits authoritative "gold" label
- **Export**: When campaign complete, admin triggers export (JSONL with sample_id, labels, metadata), downloads to feed into Crucible dataset

**Design Constraints:**

- Admin dashboard must work with Ingot's stateless architecture (no caching of Anvil data)
- Real-time updates via PubSub (leveraging ADR-005)
- Role-based access (only `:admin` role can access, see ADR-003)
- Mobile-responsive (admins may check status from phone)

## Decision

**Implement comprehensive admin dashboard as dedicated LiveView routes with queue controls, agreement visualization, label review workflows, export triggers, and audit log viewer. All data fetched from Anvil via AnvilClient, no local persistence. Real-time updates via PubSub subscriptions.**

### Architecture

```
┌────────────────────────────────────────────────┐
│        Admin Dashboard Routes                  │
│  /admin/dashboard        - Overview            │
│  /admin/queues/:id       - Queue detail        │
│  /admin/labels/:id       - Label review        │
│  /admin/audit            - Audit log           │
│  /admin/exports          - Export management   │
└────────────┬───────────────────────────────────┘
             │
             ▼
┌────────────────────────────────────────────────┐
│      AdminDashboardLive (LiveView)             │
│  - List all queues                             │
│  - Aggregate stats (total labels, avg agree)   │
│  - Recent events feed                          │
│  - Quick actions (create queue, trigger export)│
└────────────┬───────────────────────────────────┘
             │
             ▼
┌────────────────────────────────────────────────┐
│       QueueDetailLive (LiveView)               │
│  - Queue metadata (schema, policy)             │
│  - Progress chart (labeled vs remaining)       │
│  - Agreement by dimension (bar chart)          │
│  - Labeler leaderboard (velocity, agreement)   │
│  - Controls (pause/resume, modify policy)      │
└────────────┬───────────────────────────────────┘
             │
             ▼
┌────────────────────────────────────────────────┐
│       LabelReviewLive (LiveView)               │
│  - Sample display (same as labeler view)       │
│  - All labels for sample (table)               │
│  - Disagreement highlighting                   │
│  - Adjudication form (submit gold label)       │
│  - Navigation (prev/next disagreement)         │
└────────────┬───────────────────────────────────┘
             │
             ▼
        AnvilClient
          (read-only for most operations,
           write for adjudication/export)
```

### Dashboard Overview

**Route**: `/admin/dashboard`

**Features:**
- Grid of all queues with key metrics (remaining, agreement, active labelers)
- Real-time event feed (labels submitted, samples added, exports triggered)
- System health indicators (Forge/Anvil connectivity, queue backlogs)

```elixir
defmodule IngotWeb.AdminDashboardLive do
  use IngotWeb, :live_view
  alias Ingot.AnvilClient

  def mount(_params, _session, socket) do
    # Require admin role (enforced by router plug)
    Phoenix.PubSub.subscribe(Ingot.PubSub, "admin:global")

    {:ok, queues} = AnvilClient.list_queues()

    queue_stats =
      Enum.map(queues, fn queue ->
        {:ok, stats} = AnvilClient.get_queue_stats(queue.id)
        {queue.id, stats}
      end)
      |> Map.new()

    {:ok, assign(socket,
      queues: queues,
      queue_stats: queue_stats,
      recent_events: [],
      system_health: check_system_health()
    )}
  end

  def handle_info({:queue_stats_updated, queue_id, new_stats}, socket) do
    queue_stats = Map.put(socket.assigns.queue_stats, queue_id, new_stats)
    {:noreply, assign(socket, queue_stats: queue_stats)}
  end

  def handle_event("create_queue", %{"name" => name, "schema" => schema}, socket) do
    case AnvilClient.create_queue(%{name: name, label_schema: schema}) do
      {:ok, queue} ->
        queues = [queue | socket.assigns.queues]
        {:noreply, assign(socket, queues: queues)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create queue: #{reason}")}
    end
  end

  def handle_event("trigger_export", %{"queue_id" => queue_id, "format" => format}, socket) do
    case AnvilClient.trigger_export(queue_id, String.to_atom(format)) do
      {:ok, job_id} ->
        {:noreply, put_flash(socket, :info, "Export job #{job_id} started")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Export failed: #{reason}")}
    end
  end

  defp check_system_health do
    %{
      forge: check_forge_health(),
      anvil: check_anvil_health(),
      timestamp: DateTime.utc_now()
    }
  end

  defp check_forge_health do
    case Ingot.ForgeClient.health_check() do
      {:ok, _} -> :healthy
      {:error, _} -> :degraded
    end
  end

  defp check_anvil_health do
    case Ingot.AnvilClient.health_check() do
      {:ok, _} -> :healthy
      {:error, _} -> :degraded
    end
  end
end
```

**Template:**

```heex
<!-- admin_dashboard_live.html.heex -->
<div class="admin-dashboard">
  <header class="dashboard-header">
    <h1>Admin Dashboard</h1>

    <!-- System Health -->
    <div class="system-health">
      <span class={"health-indicator health-#{@system_health.forge}"}>
        Forge: <%= @system_health.forge %>
      </span>
      <span class={"health-indicator health-#{@system_health.anvil}"}>
        Anvil: <%= @system_health.anvil %>
      </span>
    </div>

    <!-- Quick Actions -->
    <div class="quick-actions">
      <button phx-click={show_modal("create-queue-modal")} class="btn-primary">
        Create Queue
      </button>
      <.link navigate={~p"/admin/audit"} class="btn-secondary">
        Audit Log
      </.link>
    </div>
  </header>

  <!-- Queue Grid -->
  <div class="queue-grid">
    <%= for queue <- @queues do %>
      <% stats = @queue_stats[queue.id] %>
      <div class="queue-card" id={"queue-#{queue.id}"}>
        <h3>
          <.link navigate={~p"/admin/queues/#{queue.id}"}>
            <%= queue.name %>
          </.link>
        </h3>

        <div class="queue-metrics">
          <div class="metric">
            <span class="metric-label">Progress</span>
            <div class="progress-bar">
              <div class="progress-fill"
                   style={"width: #{progress_pct(stats)}%"}>
              </div>
            </div>
            <span class="metric-value">
              <%= stats.assignments_completed %> / <%= stats.assignments_total %>
            </span>
          </div>

          <div class="metric">
            <span class="metric-label">Agreement</span>
            <span class={"metric-value #{agreement_class(stats.agreement_avg)}"}>
              <%= Float.round(stats.agreement_avg * 100, 1) %>%
            </span>
          </div>

          <div class="metric">
            <span class="metric-label">Active Labelers</span>
            <span class="metric-value"><%= stats.active_labelers %></span>
          </div>
        </div>

        <div class="queue-actions">
          <button phx-click="pause_queue" phx-value-queue-id={queue.id}
                  disabled={queue.status == :paused}>
            <%= if queue.status == :paused, do: "Paused", else: "Pause" %>
          </button>
          <button phx-click="trigger_export"
                  phx-value-queue-id={queue.id}
                  phx-value-format="jsonl">
            Export
          </button>
          <.link navigate={~p"/admin/labels?queue=#{queue.id}&filter=disagreements"}>
            Review Disagreements
          </.link>
        </div>
      </div>
    <% end %>
  </div>

  <!-- Recent Events Feed -->
  <div class="event-feed">
    <h2>Recent Activity</h2>
    <div class="events" id="event-list" phx-update="prepend">
      <%= for event <- @recent_events do %>
        <div class="event" id={"event-#{event.id}"}>
          <span class="event-time">
            <%= format_timestamp(event.timestamp) %>
          </span>
          <span class="event-type">
            <%= event_icon(event.type) %> <%= event.type %>
          </span>
          <span class="event-details">
            <%= event.description %>
          </span>
        </div>
      <% end %>
    </div>
  </div>
</div>

<!-- Create Queue Modal -->
<.modal id="create-queue-modal">
  <.form for={%{}} phx-submit="create_queue">
    <div class="form-group">
      <label for="queue-name">Queue Name</label>
      <input type="text" name="name" id="queue-name" required />
    </div>

    <div class="form-group">
      <label for="queue-schema">Label Schema (JSON)</label>
      <textarea name="schema" id="queue-schema" rows="10" required>
{
  "dimensions": [
    {"key": "coherence", "name": "Coherence", "type": "scale", "min": 1, "max": 5},
    {"key": "notes", "name": "Notes", "type": "text"}
  ]
}
      </textarea>
    </div>

    <div class="form-actions">
      <button type="submit" class="btn-primary">Create</button>
      <button type="button" phx-click={hide_modal("create-queue-modal")} class="btn-secondary">
        Cancel
      </button>
    </div>
  </.form>
</.modal>
```

### Queue Detail View

**Route**: `/admin/queues/:id`

**Features:**
- Queue configuration display (label schema, policy JSON)
- Progress visualization (chart: labeled vs remaining over time)
- Agreement by dimension (bar chart)
- Labeler leaderboard (table: labeler_id, labels_submitted, avg_agreement, velocity)
- Controls to modify policy, pause/resume queue

```elixir
defmodule IngotWeb.QueueDetailLive do
  use IngotWeb, :live_view
  alias Ingot.AnvilClient

  def mount(%{"id" => queue_id}, _session, socket) do
    Phoenix.PubSub.subscribe(Ingot.PubSub, "queue:#{queue_id}")

    {:ok, queue} = AnvilClient.get_queue(queue_id)
    {:ok, stats} = AnvilClient.get_queue_stats(queue_id)
    {:ok, labeler_stats} = AnvilClient.get_labeler_stats(queue_id)
    {:ok, timeline} = AnvilClient.get_progress_timeline(queue_id)

    {:ok, assign(socket,
      queue: queue,
      stats: stats,
      labeler_stats: labeler_stats,
      timeline: timeline,
      editing_policy: false
    )}
  end

  def handle_event("toggle_queue_status", _params, socket) do
    %{queue: queue} = socket.assigns
    new_status = if queue.status == :active, do: :paused, else: :active

    case AnvilClient.update_queue_status(queue.id, new_status) do
      :ok ->
        queue = %{queue | status: new_status}
        {:noreply, assign(socket, queue: queue)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update status: #{reason}")}
    end
  end

  def handle_event("update_policy", %{"policy" => policy_json}, socket) do
    case Jason.decode(policy_json) do
      {:ok, policy} ->
        case AnvilClient.update_queue_policy(socket.assigns.queue.id, policy) do
          :ok ->
            queue = %{socket.assigns.queue | policy: policy}
            {:noreply, assign(socket, queue: queue, editing_policy: false)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to update policy: #{reason}")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Invalid JSON")}
    end
  end

  def handle_info({:stats_updated, new_stats}, socket) do
    {:noreply, assign(socket, stats: new_stats)}
  end
end
```

**Template:**

```heex
<!-- queue_detail_live.html.heex -->
<div class="queue-detail">
  <header class="queue-header">
    <h1><%= @queue.name %></h1>
    <span class={"status-badge status-#{@queue.status}"}>
      <%= @queue.status %>
    </span>

    <div class="queue-actions">
      <button phx-click="toggle_queue_status" class="btn-secondary">
        <%= if @queue.status == :active, do: "Pause Queue", else: "Resume Queue" %>
      </button>
      <button phx-click="edit_policy" class="btn-secondary">
        Edit Policy
      </button>
      <.link navigate={~p"/queue/#{@queue.id}"} class="btn-secondary">
        View as Labeler
      </.link>
    </div>
  </header>

  <!-- Queue Configuration -->
  <section class="queue-config">
    <h2>Configuration</h2>

    <div class="config-section">
      <h3>Label Schema</h3>
      <pre class="code-block"><%= Jason.encode!(@queue.label_schema, pretty: true) %></pre>
    </div>

    <div class="config-section">
      <h3>Policy</h3>
      <%= if @editing_policy do %>
        <.form for={%{}} phx-submit="update_policy">
          <textarea name="policy" rows="10" class="w-full">
<%= Jason.encode!(@queue.policy, pretty: true) %>
          </textarea>
          <div class="form-actions">
            <button type="submit" class="btn-primary">Save</button>
            <button type="button" phx-click="cancel_edit_policy" class="btn-secondary">
              Cancel
            </button>
          </div>
        </.form>
      <% else %>
        <pre class="code-block"><%= Jason.encode!(@queue.policy, pretty: true) %></pre>
      <% end %>
    </div>
  </section>

  <!-- Progress Visualization -->
  <section class="queue-stats">
    <h2>Progress</h2>

    <div class="chart-container">
      <!-- Line chart: X=time, Y=assignments completed -->
      <canvas id="progress-chart"
              phx-hook="ProgressChart"
              data-timeline={Jason.encode!(@timeline)}>
      </canvas>
    </div>

    <div class="stats-grid">
      <div class="stat-card">
        <span class="stat-label">Completed</span>
        <span class="stat-value"><%= @stats.assignments_completed %></span>
      </div>
      <div class="stat-card">
        <span class="stat-label">Remaining</span>
        <span class="stat-value"><%= @stats.assignments_remaining %></span>
      </div>
      <div class="stat-card">
        <span class="stat-label">Avg Agreement</span>
        <span class="stat-value">
          <%= Float.round(@stats.agreement_avg * 100, 1) %>%
        </span>
      </div>
      <div class="stat-card">
        <span class="stat-label">Velocity</span>
        <span class="stat-value"><%= @stats.labels_per_hour %>/hr</span>
      </div>
    </div>
  </section>

  <!-- Agreement by Dimension -->
  <section class="agreement-breakdown">
    <h2>Agreement by Dimension</h2>

    <div class="chart-container">
      <!-- Bar chart: X=dimension, Y=agreement % -->
      <canvas id="agreement-chart"
              phx-hook="AgreementChart"
              data-dimensions={Jason.encode!(@stats.agreement_by_dimension)}>
      </canvas>
    </div>
  </section>

  <!-- Labeler Leaderboard -->
  <section class="labeler-leaderboard">
    <h2>Labeler Performance</h2>

    <table class="data-table">
      <thead>
        <tr>
          <th>Labeler</th>
          <th>Labels Submitted</th>
          <th>Avg Agreement</th>
          <th>Velocity (labels/hr)</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        <%= for labeler_stat <- @labeler_stats do %>
          <tr>
            <td><%= labeler_stat.labeler_email %></td>
            <td><%= labeler_stat.labels_submitted %></td>
            <td class={agreement_class(labeler_stat.agreement_avg)}>
              <%= Float.round(labeler_stat.agreement_avg * 100, 1) %>%
            </td>
            <td><%= Float.round(labeler_stat.velocity, 1) %></td>
            <td>
              <.link navigate={~p"/admin/labels?labeler=#{labeler_stat.labeler_id}"}>
                Review Labels
              </.link>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </section>
</div>
```

### Label Review & Adjudication

**Route**: `/admin/labels/:sample_id` or `/admin/labels?queue=X&filter=disagreements`

**Features:**
- Display sample (same component as labeler view)
- Table of all labels for sample (labeler, timestamp, label values)
- Highlight disagreements (cells where labels differ significantly)
- Adjudication form (admin submits "gold" label that overrides)
- Navigation to next disagreement

```elixir
defmodule IngotWeb.LabelReviewLive do
  use IngotWeb, :live_view
  alias Ingot.{AnvilClient, ForgeClient}

  def mount(%{"sample_id" => sample_id}, _session, socket) do
    {:ok, sample} = ForgeClient.get_sample(sample_id)
    {:ok, labels} = AnvilClient.get_label_history(sample_id)
    {:ok, queue} = AnvilClient.get_queue(List.first(labels).queue_id)

    disagreements = identify_disagreements(labels, queue.label_schema)

    {:ok, assign(socket,
      sample: sample,
      labels: labels,
      queue: queue,
      disagreements: disagreements,
      adjudication_data: %{}
    )}
  end

  def handle_event("submit_adjudication", params, socket) do
    %{sample: sample, queue: queue, adjudication_data: data} = socket.assigns

    case AnvilClient.submit_adjudication(sample.id, queue.id, data) do
      :ok ->
        {:noreply, push_navigate(socket, to: next_disagreement_url(socket))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Adjudication failed: #{reason}")}
    end
  end

  defp identify_disagreements(labels, schema) do
    # Group labels by dimension, calculate variance
    schema.dimensions
    |> Enum.map(fn dim ->
      values = Enum.map(labels, & &1.label_data[dim.key])
      variance = calculate_variance(values)

      {dim.key, %{variance: variance, values: values, threshold: dim.disagreement_threshold || 1.0}}
    end)
    |> Enum.filter(fn {_key, meta} -> meta.variance > meta.threshold end)
    |> Map.new()
  end

  defp calculate_variance(values) do
    mean = Enum.sum(values) / length(values)
    Enum.reduce(values, 0, fn v, acc -> acc + :math.pow(v - mean, 2) end) / length(values)
  end
end
```

**Template:**

```heex
<!-- label_review_live.html.heex -->
<div class="label-review">
  <header class="review-header">
    <h1>Label Review: <%= @sample.id %></h1>
    <div class="navigation">
      <button phx-click="prev_disagreement" class="btn-secondary">
        ← Previous
      </button>
      <button phx-click="next_disagreement" class="btn-secondary">
        Next →
      </button>
    </div>
  </header>

  <!-- Sample Display (reuse component from labeling view) -->
  <section class="sample-section">
    <.sample_display sample={@sample} />
  </section>

  <!-- Labels Table -->
  <section class="labels-section">
    <h2>Submitted Labels</h2>

    <table class="labels-table">
      <thead>
        <tr>
          <th>Labeler</th>
          <th>Timestamp</th>
          <%= for dim <- @queue.label_schema.dimensions do %>
            <th>
              <%= dim.name %>
              <%= if Map.has_key?(@disagreements, dim.key) do %>
                <span class="disagreement-indicator" title="High variance">⚠️</span>
              <% end %>
            </th>
          <% end %>
          <th>Notes</th>
        </tr>
      </thead>
      <tbody>
        <%= for label <- @labels do %>
          <tr>
            <td><%= label.labeler_email %></td>
            <td><%= format_timestamp(label.submitted_at) %></td>
            <%= for dim <- @queue.label_schema.dimensions do %>
              <td class={disagreement_cell_class(@disagreements, dim.key, label.label_data[dim.key])}>
                <%= label.label_data[dim.key] %>
              </td>
            <% end %>
            <td class="notes-cell"><%= label.label_data[:notes] %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </section>

  <!-- Adjudication Form -->
  <%= if @disagreements != %{} do %>
    <section class="adjudication-section">
      <h2>Adjudication</h2>
      <p class="help-text">
        This sample has disagreements. Submit a gold label to resolve.
      </p>

      <.form for={@adjudication_data} phx-submit="submit_adjudication">
        <div class="label-dimensions">
          <%= for dim <- @queue.label_schema.dimensions do %>
            <div class="dimension">
              <label><%= dim.name %></label>
              <%= if dim.type == "scale" do %>
                <input type="range"
                       name={"adjudication_data[#{dim.key}]"}
                       min={dim.min}
                       max={dim.max}
                       value={@adjudication_data[dim.key] || median_value(@labels, dim.key)} />
                <span class="dimension-value">
                  <%= @adjudication_data[dim.key] || median_value(@labels, dim.key) %>
                </span>
              <% else %>
                <textarea name={"adjudication_data[#{dim.key}]"}><%= @adjudication_data[dim.key] %></textarea>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="form-actions">
          <button type="submit" class="btn-primary">Submit Gold Label</button>
          <button type="button" phx-click="skip_adjudication" class="btn-secondary">
            Skip
          </button>
        </div>
      </.form>
    </section>
  <% end %>
</div>
```

### Export Management

**Route**: `/admin/exports`

**Features:**
- List of export jobs (queued, running, completed, failed)
- Trigger new export (select queue, format: JSONL/CSV/Parquet)
- Download completed exports
- View export logs

```elixir
defmodule IngotWeb.ExportManagementLive do
  use IngotWeb, :live_view
  alias Ingot.AnvilClient

  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(Ingot.PubSub, "exports:updates")

    {:ok, exports} = AnvilClient.list_exports()

    {:ok, assign(socket, exports: exports)}
  end

  def handle_event("trigger_export", %{"queue_id" => queue_id, "format" => format}, socket) do
    case AnvilClient.trigger_export(queue_id, String.to_atom(format)) do
      {:ok, job_id} ->
        {:noreply, put_flash(socket, :info, "Export #{job_id} started")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Export failed: #{reason}")}
    end
  end

  def handle_info({:export_completed, export_id}, socket) do
    {:ok, updated_export} = AnvilClient.get_export(export_id)

    exports =
      Enum.map(socket.assigns.exports, fn exp ->
        if exp.id == export_id, do: updated_export, else: exp
      end)

    {:noreply, assign(socket, exports: exports)}
  end
end
```

### Audit Log Viewer

**Route**: `/admin/audit`

**Features:**
- Filterable log of all system events (label submission, queue creation, policy changes, exports)
- Search by user, event type, date range
- Export audit log for compliance

```elixir
defmodule IngotWeb.AuditLogLive do
  use IngotWeb, :live_view
  alias Ingot.AnvilClient

  def mount(_params, _session, socket) do
    {:ok, events} = AnvilClient.get_audit_log(limit: 100)

    {:ok, assign(socket,
      events: events,
      filters: %{event_type: nil, user_id: nil, date_from: nil, date_to: nil}
    )}
  end

  def handle_event("apply_filters", filters, socket) do
    {:ok, events} = AnvilClient.get_audit_log(filters: filters, limit: 100)

    {:noreply, assign(socket, events: events, filters: filters)}
  end
end
```

## Consequences

### Positive

- **Comprehensive Visibility**: Admins have full insight into labeling campaigns (progress, quality, labeler performance) without manual queries.

- **Quality Control**: Disagreement detection and adjudication workflows ensure high-quality labeled datasets. Admins can intervene before agreement drops too low.

- **Operational Efficiency**: Queue controls (pause/resume, policy updates) let admins adapt to changing research needs (e.g., increase redundancy for critical samples).

- **Compliance**: Audit log provides complete provenance trail (required for ML reproducibility, regulatory compliance in some domains).

- **Export Automation**: One-click exports to multiple formats streamline integration with Crucible datasets and downstream training pipelines.

### Negative

- **Complex UI**: Admin dashboard has many features, risk of overwhelming users.
  - *Mitigation*: Progressive disclosure (most features hidden behind tabs/modals). Default view shows only essential metrics.

- **Heavy Client Queries**: Fetching labeler stats, timelines, and label history requires multiple AnvilClient calls (potentially slow).
  - *Mitigation*: Anvil provides aggregate endpoints (e.g., `GET /queues/:id/stats` returns pre-computed stats). Cache in LiveView process for session.

- **Real-Time Update Overhead**: Admin dashboards subscribed to PubSub for all queues could receive high event volume.
  - *Mitigation*: Throttle updates (batch events, send max 1 update/sec). Use Phoenix.Tracker for presence tracking instead of broadcasts.

### Neutral

- **Adjudication Workflow**: Manual adjudication is time-consuming. For large-scale campaigns (1000+ disagreements), consider ML-assisted adjudication.
  - Future: Train model to predict gold labels based on historical adjudications. Flag only uncertain cases for human review.

- **Export Formats**: Initial support for JSONL. CSV and Parquet require additional serialization logic in Anvil.
  - Phased rollout: JSONL in v1, CSV/Parquet in v2.

## Implementation Checklist

1. Implement `AdminDashboardLive` (overview, queue grid, event feed)
2. Implement `QueueDetailLive` (config, progress chart, agreement chart, leaderboard)
3. Add Chart.js hooks for progress and agreement visualization
4. Implement `LabelReviewLive` (sample display, labels table, adjudication form)
5. Add disagreement detection logic (variance calculation)
6. Implement `ExportManagementLive` (job list, trigger, download)
7. Implement `AuditLogLive` (event list, filters, export)
8. Extend AnvilClient with admin endpoints:
   - `list_queues/0`
   - `get_queue_stats/1`
   - `get_labeler_stats/1`
   - `get_progress_timeline/1`
   - `update_queue_status/2`
   - `update_queue_policy/2`
   - `submit_adjudication/3`
   - `list_exports/0`
   - `trigger_export/2`
   - `get_audit_log/1`
9. Add authorization checks (require `:admin` role) to router
10. Write tests for admin workflows (create queue, adjudicate, export)
11. Document admin features in user guide

## Related ADRs

- ADR-003: Auth Strategy (admin role enforcement)
- ADR-005: Realtime UX (PubSub subscriptions, LiveView updates)
- ADR-002: Client Layer Design (AnvilClient admin endpoints)
