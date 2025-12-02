# ADR-004: Real-time Progress Updates (PubSub)

## Status

Accepted

## Context

Multiple labelers may work simultaneously, and we want to show real-time progress updates to all active users. Progress metrics include:

- Total labels completed across all users
- Number of active labelers
- Queue depth (remaining samples)
- Labels per hour (velocity)

We need a mechanism to broadcast these updates efficiently.

## Decision

Use **Phoenix PubSub** for broadcasting progress updates:

### Architecture

```
┌─────────────────┐
│  LabelingLive   │──┐
│   (Labeler 1)   │  │
└─────────────────┘  │
                     │
┌─────────────────┐  │    ┌──────────────┐
│  LabelingLive   │──┼───▶│ Phoenix      │
│   (Labeler 2)   │  │    │ PubSub       │
└─────────────────┘  │    │ ("progress") │
                     │    └──────────────┘
┌─────────────────┐  │            │
│  LabelingLive   │──┘            │
│   (Labeler 3)   │               │
└─────────────────┘               │
                                  ▼
                         ┌─────────────────┐
                         │  DashboardLive  │
                         │  (Admin View)   │
                         └─────────────────┘
```

### PubSub Topics

- `"progress:labels"`: Label completion events
- `"progress:users"`: User join/leave events
- `"progress:queue"`: Queue depth updates

### Event Broadcasting

When a label is submitted:

```elixir
Phoenix.PubSub.broadcast(
  Ingot.PubSub,
  "progress:labels",
  {:label_completed, %{session_id: id, timestamp: now}}
)
```

### Event Subscription

LiveView processes subscribe on mount:

```elixir
def mount(_params, _session, socket) do
  Phoenix.PubSub.subscribe(Ingot.PubSub, "progress:labels")
  Phoenix.PubSub.subscribe(Ingot.PubSub, "progress:users")
  {:ok, socket}
end
```

### Event Handling

```elixir
def handle_info({:label_completed, _data}, socket) do
  {:noreply, update_progress_counter(socket)}
end
```

## Rationale

### Why PubSub?

1. **Built-in**: Native Phoenix functionality
2. **Scalable**: Works across distributed nodes
3. **Efficient**: Direct process messaging
4. **Real-time**: Instant updates to all subscribers
5. **Simple**: Minimal code required

### Why Not Polling?

Polling would require:
- Periodic HTTP requests from each client
- Database queries on every poll
- Higher latency (poll interval delay)
- More server load

### Why Not WebSockets Directly?

Phoenix PubSub abstracts WebSocket complexity:
- Automatic connection management
- Built-in reconnection logic
- Topic-based routing
- Cluster-aware broadcasting

## Consequences

### Positive

- **Real-time UX**: Progress updates appear instantly
- **Collaborative Feel**: Users see others' progress
- **Low Latency**: Direct process messaging
- **Scalable**: Efficient broadcast to many subscribers
- **Simple Code**: Minimal implementation overhead

### Negative

- **Message Volume**: High labeling velocity → many messages
- **Memory Usage**: Each subscriber holds topic state
- **Stale Data Risk**: Clients may have slightly different state

### Mitigation

- Throttle broadcasts (max 1 update per second)
- Use delta updates instead of full state
- Implement eventual consistency pattern
- Add client-side debouncing

## Progress Metrics

### Metrics Tracked

1. **Total Labels**: Cumulative count across all sessions
2. **Active Labelers**: Count of connected LiveView processes
3. **Queue Depth**: Samples remaining to be labeled
4. **Velocity**: Labels per hour (rolling average)
5. **Session Stats**: Per-session completion counts

### Metrics Storage

- **In-Memory**: Current active labelers (ETS or Agent)
- **Anvil**: Persistent label counts
- **Calculated**: Velocity computed from timestamps

### Metrics Display

Progress component shows:
```
┌─────────────────────────────────────┐
│  Progress                           │
│  ────────────────────────            │
│  47 / 500 labeled (9.4%)            │
│  3 active labelers                  │
│  ~15 labels/hour                    │
└─────────────────────────────────────┘
```

## Update Frequency

### Throttling Strategy

- **Label Events**: Broadcast immediately, aggregate in clients
- **Progress Updates**: Max 1 UI update per second
- **User Count**: Update every 5 seconds
- **Queue Depth**: Update every 30 seconds

Implementation using `handle_info` debouncing:

```elixir
def handle_info({:label_completed, _}, socket) do
  # Increment counter immediately
  socket = update(socket, :pending_updates, &(&1 + 1))

  # Schedule debounced UI update if not already scheduled
  if socket.assigns[:update_scheduled] do
    {:noreply, socket}
  else
    Process.send_after(self(), :flush_updates, 1000)
    {:noreply, assign(socket, :update_scheduled, true)}
  end
end

def handle_info(:flush_updates, socket) do
  # Update UI with all pending changes
  socket =
    socket
    |> assign(:update_scheduled, false)
    |> assign(:labels_completed, fetch_total_labels())
    |> assign(:pending_updates, 0)

  {:noreply, socket}
end
```

## Cluster Considerations

Phoenix PubSub works across distributed nodes:

### Cluster-Aware Broadcasting

```elixir
# Automatically broadcasts to all nodes
Phoenix.PubSub.broadcast(
  Ingot.PubSub,
  "progress:labels",
  {:label_completed, data}
)
```

### Active User Counting

Use distributed registry (Phoenix.Tracker):

```elixir
# Track user presence across nodes
Ingot.Presence.track(
  self(),
  "labelers",
  user_id,
  %{joined_at: now}
)
```

## Alternatives Considered

### 1. Database Polling

Query database every N seconds for updates.

**Rejected because:**
- Higher latency (poll interval)
- Increased database load
- Wasted queries when no changes
- Poor scalability

### 2. Server-Sent Events (SSE)

Use SSE instead of WebSockets.

**Rejected because:**
- One-way communication only
- LiveView already uses WebSockets
- Redundant connection overhead

### 3. GraphQL Subscriptions

Use GraphQL subscriptions for real-time data.

**Rejected because:**
- Adds GraphQL dependency
- More complex than PubSub
- Overkill for simple progress updates

### 4. Redis Pub/Sub

Use Redis for message broadcasting.

**Rejected because:**
- External dependency
- Phoenix PubSub sufficient
- Additional operational complexity

## Implementation Details

### PubSub Configuration

```elixir
# lib/ingot/application.ex
children = [
  {Phoenix.PubSub, name: Ingot.PubSub},
  # ...
]
```

### Broadcasting Helper

```elixir
# lib/ingot/progress.ex
defmodule Ingot.Progress do
  def broadcast_label_completed(session_id) do
    Phoenix.PubSub.broadcast(
      Ingot.PubSub,
      "progress:labels",
      {:label_completed, session_id, DateTime.utc_now()}
    )
  end

  def broadcast_user_joined(user_id) do
    Phoenix.PubSub.broadcast(
      Ingot.PubSub,
      "progress:users",
      {:user_joined, user_id}
    )
  end
end
```

### Subscription in LiveView

```elixir
def mount(_params, _session, socket) do
  if connected?(socket) do
    Phoenix.PubSub.subscribe(Ingot.PubSub, "progress:labels")
    Phoenix.PubSub.subscribe(Ingot.PubSub, "progress:users")
    Ingot.Progress.broadcast_user_joined(socket.assigns.user_id)
  end

  {:ok, assign(socket, labels_completed: 0, active_labelers: 0)}
end
```

## Testing Strategy

### Unit Tests

- Test broadcast functions send correct messages
- Verify subscribers receive broadcasted events
- Test throttling/debouncing logic

### Integration Tests

- Test multi-user scenarios with concurrent labelers
- Verify progress updates propagate correctly
- Test reconnection behavior

### Example Test

```elixir
test "broadcasting label completion updates all subscribers" do
  {:ok, view1, _html} = live(conn, "/label")
  {:ok, view2, _html} = live(conn, "/label")

  # Submit label from view1
  view1 |> element("#submit-button") |> render_click()

  # Verify view2 receives update
  assert render(view2) =~ "1 / 500 labeled"
end
```

## References

- [Phoenix PubSub Documentation](https://hexdocs.pm/phoenix_pubsub/)
- [Phoenix.Tracker Documentation](https://hexdocs.pm/phoenix/Phoenix.Tracker.html)
- [ADR-002: LiveView Labeling Interface Design](002-liveview-labeling-interface.md)
