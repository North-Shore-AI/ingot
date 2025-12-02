# ADR-001: Stateless UI Architecture

## Status
Accepted

## Context

Ingot serves as a user interface layer over two domain-specific services:
- **Forge**: Sample generation factory responsible for pipeline orchestration, sample storage, artifact management, and measurement recording
- **Anvil**: Labeling queue manager handling assignment distribution, label collection, agreement calculation, and audit trails

The initial implementation (v0.1) demonstrated basic LiveView capabilities but lacked clear architectural boundaries. The question arose: should Ingot maintain its own database of samples, labels, and user data, or should it remain a purely presentational layer?

**Key Design Tensions:**
1. **Data Ownership**: Duplicating samples/labels in Ingot would create synchronization complexity, stale data risks, and lineage ambiguity
2. **Performance**: Statelessness might require repeated calls to upstream services, potentially impacting latency
3. **Deployment Flexibility**: Stateful services require persistent storage, backups, and migration management
4. **Failure Modes**: If Ingot caches domain data, cache invalidation and consistency become critical failure vectors

The system must support:
- Real-time labeling workflows with sub-second response times
- Multi-user concurrent access to shared queues
- Admin dashboards displaying aggregate metrics
- Future multi-tenant deployments
- CNS experiments requiring complex sample rendering (narratives, claims, synthesis results)

## Decision

**Ingot will operate as a thin, stateless UI layer that delegates all domain logic and data ownership to Forge and Anvil.**

### Core Principles

1. **No Domain Data Persistence**: Ingot will not store samples, labels, pipelines, queues, or measurements in its own database
   - All sample data is fetched from Forge via `Ingot.ForgeClient`
   - All labeling operations flow through Anvil via `Ingot.AnvilClient`
   - No local caching beyond the LiveView process lifecycle (seconds to minutes)

2. **Session-Scoped State Only**: The only state Ingot maintains is ephemeral and user-specific:
   - UI preferences (theme, keyboard shortcuts, display density)
   - In-progress form data (partially completed labels)
   - Pagination cursors and filter settings
   - Client-side progress indicators
   - All stored in Phoenix LiveView assigns or browser localStorage

3. **Direct Client Calls**: Ingot communicates with Forge and Anvil through dedicated client modules:
   ```elixir
   # ForgeClient: read-only sample access
   {:ok, sample} = Ingot.ForgeClient.get_sample(sample_id)
   {:ok, artifacts} = Ingot.ForgeClient.get_artifacts(sample_id)
   {:ok, stream} = Ingot.ForgeClient.stream_batch(pipeline_id, limit: 100)

   # AnvilClient: labeling operations
   {:ok, assignment} = Ingot.AnvilClient.get_next_assignment(queue_id, labeler_id)
   :ok = Ingot.AnvilClient.submit_label(assignment_id, label_data)
   {:ok, stats} = Ingot.AnvilClient.get_queue_stats(queue_id)
   ```

4. **DTO Layer for Decoupling**: Client modules translate internal Forge/Anvil structs into UI-friendly DTOs:
   ```elixir
   # Ingot.DTO.Sample - simplified representation
   defstruct [:id, :pipeline_id, :payload, :artifacts, :metadata, :created_at]

   # Ingot.DTO.Assignment - labeling task
   defstruct [:id, :queue_id, :sample, :schema, :existing_labels, :assigned_at]
   ```

5. **Read-Through Pattern**: LiveView processes fetch data on mount/handle_event, no background synchronization:
   ```elixir
   def mount(%{"assignment_id" => id}, _session, socket) do
     case AnvilClient.get_assignment(id) do
       {:ok, assignment} ->
         sample = ForgeClient.get_sample(assignment.sample_id)
         {:ok, assign(socket, assignment: assignment, sample: sample)}
       {:error, :not_found} ->
         {:ok, push_navigate(socket, to: ~p"/queue")}
     end
   end
   ```

### What Ingot Does NOT Store

- ❌ Samples or sample payloads
- ❌ Labels or label history
- ❌ Queue definitions or policies
- ❌ Pipeline configurations
- ❌ Artifact blobs (uses signed URLs from Forge)
- ❌ Agreement metrics (computed by Anvil)
- ❌ Audit logs (maintained by Anvil)

### Optional Auth Schema

Ingot MAY maintain a minimal auth schema if not using external IdP (OIDC):
```sql
-- Minimal local auth (if not using OIDC)
CREATE TABLE ingot_users (
  id UUID PRIMARY KEY,
  external_id TEXT UNIQUE,  -- from IdP
  email TEXT UNIQUE,
  created_at TIMESTAMP
);

CREATE TABLE ingot_sessions (
  token TEXT PRIMARY KEY,
  user_id UUID REFERENCES ingot_users(id),
  expires_at TIMESTAMP
);
```

However, **role definitions and permissions are stored in Anvil** (as they govern labeling access). Ingot reads roles via `AnvilClient.get_user_roles(user_id)`.

## Consequences

### Positive

- **Single Source of Truth**: Forge owns samples, Anvil owns labels. No synchronization bugs or stale data.
- **Horizontal Scalability**: Stateless web nodes can be added/removed without data migration. Load balancer can route to any node.
- **Simplified Deployment**: No database migrations for Ingot releases. Config points to Forge/Anvil endpoints via ENV vars.
- **Clear Boundaries**: Domain logic lives in domain services. Ingot focuses purely on presentation and interaction.
- **Failure Isolation**: If Ingot crashes/restarts, no data loss. Users reload and continue from authoritative state.
- **Multi-Tenancy Ready**: Different Ingot instances can point to different Forge/Anvil clusters without shared state concerns.

### Negative

- **Latency Sensitivity**: Every UI operation requires round-trip to Forge/Anvil. Network latency becomes visible.
  - *Mitigation*: Deploy Ingot in same cluster as Forge/Anvil. Use direct Elixir calls (not HTTP) when co-located.
  - *Mitigation*: Implement read-through caching in LiveView process for single-session data (cache invalidation = process death).

- **Network Dependency**: Ingot cannot function if Forge/Anvil are unreachable.
  - *Mitigation*: Circuit breakers in client modules. Degrade gracefully (show cached assignment, disable new fetches).
  - *Mitigation*: Health checks expose upstream dependency status.

- **Query Complexity**: Admin dashboards requiring joins across samples/labels need multiple service calls.
  - *Mitigation*: Forge/Anvil provide aggregate endpoints (e.g., `GET /queues/:id/stats` returns samples_labeled, agreement_by_dimension).
  - *Mitigation*: Accept slightly higher latency for admin views (humans can tolerate 500ms-1s for dashboards).

- **Limited Offline Support**: Stateless design prevents offline labeling workflows.
  - *Mitigation*: Addressed in ADR-010. For CNS, online-only is acceptable (labelers work in browser sessions).

### Neutral

- **Client Module Complexity**: ForgeClient/AnvilClient become critical abstraction boundaries requiring careful API design (see ADR-002).
- **Telemetry Indirection**: Ingot must subscribe to Forge/Anvil telemetry events rather than emitting primary metrics (see ADR-008).
- **Session Storage**: UI preferences need client-side storage (localStorage) or minimal server-side session table.

## Implementation Notes

### LiveView Lifecycle Integration

```elixir
defmodule IngotWeb.LabelingLive do
  use IngotWeb, :live_view
  alias Ingot.{ForgeClient, AnvilClient}

  def mount(%{"queue_id" => queue_id}, %{"user_id" => user_id}, socket) do
    # Fetch assignment from Anvil
    case AnvilClient.get_next_assignment(queue_id, user_id) do
      {:ok, assignment} ->
        # Fetch sample from Forge
        {:ok, sample} = ForgeClient.get_sample(assignment.sample_id)

        # Subscribe to real-time updates
        Phoenix.PubSub.subscribe(Ingot.PubSub, "queue:#{queue_id}")

        {:ok, assign(socket,
          assignment: assignment,
          sample: sample,
          label_data: %{},
          queue_id: queue_id
        )}

      {:error, :no_assignments} ->
        {:ok, assign(socket, :no_work, true)}
    end
  end

  def handle_event("submit_label", params, socket) do
    %{assignment: assignment, label_data: label_data} = socket.assigns

    case AnvilClient.submit_label(assignment.id, label_data) do
      :ok ->
        # Fetch next assignment
        {:ok, next_assignment} = AnvilClient.get_next_assignment(socket.assigns.queue_id, ...)
        {:ok, next_sample} = ForgeClient.get_sample(next_assignment.sample_id)

        {:noreply, assign(socket,
          assignment: next_assignment,
          sample: next_sample,
          label_data: %{}
        )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Submission failed: #{reason}")}
    end
  end
end
```

### Error Handling Pattern

All client calls use `{:ok, result} | {:error, reason}` tuples. LiveViews handle errors with user-facing messages:

```elixir
case ForgeClient.get_sample(sample_id) do
  {:ok, sample} ->
    {:ok, assign(socket, sample: sample)}

  {:error, :not_found} ->
    {:ok, redirect(socket, to: ~p"/error/sample_not_found")}

  {:error, :timeout} ->
    {:ok, put_flash(socket, :error, "Forge is slow, please retry")}

  {:error, :network} ->
    {:ok, put_flash(socket, :error, "Cannot reach Forge service")}
end
```

## Related ADRs

- ADR-002: Client Layer Design (defines ForgeClient/AnvilClient APIs)
- ADR-003: Auth Strategy (minimal local state for sessions)
- ADR-004: Persistence Strategy (shared Postgres, no per-repo instances)
- ADR-008: Telemetry & Observability (subscribing to upstream events)
