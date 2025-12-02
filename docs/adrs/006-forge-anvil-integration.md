# ADR-006: Integration with Forge and Anvil

## Status

Accepted

## Context

Ingot depends on two external libraries:

- **Forge**: Sample generation library (creates narrative synthesis samples)
- **Anvil**: Label storage library (persists human labels)

We need to define clear integration patterns and boundaries between these libraries and Ingot.

## Decision

Use **path dependencies** with clear **functional boundaries**:

### Dependency Configuration

```elixir
# mix.exs
defp deps do
  [
    {:forge, path: "../forge"},
    {:anvil, path: "../anvil"},
    # ... other deps
  ]
end
```

### Integration Architecture

```
┌─────────────────────────────────────────────────────┐
│                      Ingot                          │
│  ┌───────────────────────────────────────────────┐  │
│  │           IngotWeb.LabelingLive               │  │
│  │  ┌────────────────┐    ┌──────────────────┐  │  │
│  │  │ Fetch Sample   │───▶│ Display Sample   │  │  │
│  │  └────────────────┘    └──────────────────┘  │  │
│  │          │                       │            │  │
│  │          ▼                       ▼            │  │
│  │  ┌────────────────┐    ┌──────────────────┐  │  │
│  │  │ Submit Label   │◀───│ Collect Ratings  │  │  │
│  │  └────────────────┘    └──────────────────┘  │  │
│  └─────────┬──────────────────────┬──────────────┘  │
│            │                      │                 │
│            ▼                      ▼                 │
│    ┌──────────────┐      ┌──────────────────┐      │
│    │ Forge Client │      │  Anvil Client    │      │
│    └──────────────┘      └──────────────────┘      │
└────────────┬────────────────────────┬───────────────┘
             │                        │
             ▼                        ▼
    ┌────────────────┐      ┌──────────────────┐
    │  Forge Library │      │  Anvil Library   │
    │                │      │                  │
    │ • Generate     │      │ • Store labels   │
    │   samples      │      │ • Query labels   │
    │ • Manage queue │      │ • Export data    │
    │ • Validate     │      │ • Statistics     │
    └────────────────┘      └──────────────────┘
```

### Forge Integration

**Responsibility**: Fetch samples to be labeled

```elixir
defmodule Ingot.ForgeClient do
  @moduledoc """
  Client for interacting with Forge sample generation library.
  Thin wrapper that delegates all logic to Forge.
  """

  @doc "Fetch next sample from queue"
  def fetch_next_sample(user_id) do
    Forge.Queue.fetch_next(user_id)
  end

  @doc "Mark sample as skipped"
  def skip_sample(sample_id, user_id) do
    Forge.Queue.skip(sample_id, user_id)
  end

  @doc "Get queue statistics"
  def queue_stats do
    Forge.Queue.stats()
  end

  @doc "Generate new batch of samples"
  def generate_batch(count) do
    Forge.Generator.generate(count)
  end
end
```

### Anvil Integration

**Responsibility**: Store and retrieve labels

```elixir
defmodule Ingot.AnvilClient do
  @moduledoc """
  Client for interacting with Anvil label storage library.
  Thin wrapper that delegates all logic to Anvil.
  """

  @doc "Store a completed label"
  def store_label(label) do
    Anvil.Labels.store(label)
  end

  @doc "Get total label count"
  def total_labels do
    Anvil.Labels.count()
  end

  @doc "Get labels for a specific session"
  def session_labels(session_id) do
    Anvil.Labels.for_session(session_id)
  end

  @doc "Export all labels as CSV"
  def export_csv do
    Anvil.Export.to_csv()
  end

  @doc "Get labeling statistics"
  def statistics do
    Anvil.Statistics.summary()
  end
end
```

## Data Flow

### Labeling Workflow

1. **Mount**: LiveView mounts, user_id generated
2. **Fetch**: `ForgeClient.fetch_next_sample(user_id)` retrieves sample
3. **Display**: Sample data shown in UI
4. **Label**: User provides ratings and notes
5. **Store**: `AnvilClient.store_label(label)` persists label
6. **Broadcast**: PubSub notifies other users of progress
7. **Repeat**: Fetch next sample

### Sample Data Structure

Forge provides:

```elixir
%{
  id: "sample-uuid",
  narrative_a: "Text of narrative A...",
  narrative_b: "Text of narrative B...",
  synthesis: "Synthesized text combining both narratives...",
  metadata: %{
    generated_at: ~U[2025-01-15 10:30:00Z],
    model: "gpt-4",
    temperature: 0.7
  }
}
```

### Label Data Structure

Ingot sends to Anvil:

```elixir
%{
  sample_id: "sample-uuid",
  session_id: "session-uuid",
  user_id: "user-uuid",
  ratings: %{
    coherence: 4,
    grounded: 5,
    novel: 3,
    balanced: 4
  },
  notes: "Optional free-form notes",
  time_spent_ms: 45000,
  labeled_at: ~U[2025-01-15 10:31:00Z]
}
```

## Error Handling

### Forge Errors

Handle sample fetch failures:

```elixir
case ForgeClient.fetch_next_sample(user_id) do
  {:ok, sample} ->
    {:noreply, assign(socket, :current_sample, sample)}

  {:error, :queue_empty} ->
    {:noreply, push_navigate(socket, to: "/complete")}

  {:error, reason} ->
    {:noreply, put_flash(socket, :error, "Failed to fetch sample: #{reason}")}
end
```

### Anvil Errors

Handle label storage failures:

```elixir
case AnvilClient.store_label(label) do
  {:ok, _stored_label} ->
    broadcast_label_completed(session_id)
    {:noreply, fetch_next_sample(socket)}

  {:error, reason} ->
    # Keep label in socket state for retry
    socket =
      socket
      |> assign(:pending_label, label)
      |> put_flash(:error, "Failed to save label. Please try again.")

    {:noreply, socket}
end
```

## Library Boundaries

### What Ingot Does

- Render UI components
- Handle user interactions
- Manage LiveView state
- Call Forge and Anvil functions
- Broadcast PubSub events

### What Ingot Does NOT Do

- Generate samples (Forge's job)
- Validate sample content (Forge's job)
- Store labels (Anvil's job)
- Calculate statistics (Anvil's job)
- Implement business logic

### Boundary Enforcement

Code review checklist:

- [ ] No sample generation logic in Ingot
- [ ] No label storage logic in Ingot
- [ ] No business rules in Ingot
- [ ] All domain logic delegates to Forge/Anvil
- [ ] Client modules are thin wrappers only

## Testing Strategy

### Unit Tests

Test Ingot's client modules in isolation:

```elixir
defmodule Ingot.ForgeClientTest do
  use ExUnit.Case, async: true

  import Mox

  setup :verify_on_exit!

  test "fetch_next_sample delegates to Forge" do
    expect(ForgeMock, :fetch_next, fn user_id ->
      assert user_id == "user-123"
      {:ok, %{id: "sample-1"}}
    end)

    assert {:ok, %{id: "sample-1"}} =
             ForgeClient.fetch_next_sample("user-123")
  end
end
```

### Integration Tests

Test actual integration with Forge and Anvil:

```elixir
defmodule IngotWeb.LabelingLiveIntegrationTest do
  use IngotWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "complete labeling workflow", %{conn: conn} do
    # Generate sample via Forge
    {:ok, sample} = Forge.Generator.generate_one()

    # Load labeling interface
    {:ok, view, _html} = live(conn, "/label")

    # Verify sample displayed
    assert render(view) =~ sample.narrative_a

    # Submit label
    view
    |> form("#label-form", label: %{
      coherence: 4,
      grounded: 5,
      novel: 3,
      balanced: 4,
      notes: "Good synthesis"
    })
    |> render_submit()

    # Verify label stored in Anvil
    labels = Anvil.Labels.all()
    assert length(labels) == 1
    assert hd(labels).ratings.coherence == 4
  end
end
```

### Mock Strategy

Use Mox for unit testing:

```elixir
# test/support/mocks.ex
Mox.defmock(ForgeMock, for: Forge.Behaviour)
Mox.defmock(AnvilMock, for: Anvil.Behaviour)
```

Configure in test.exs:

```elixir
config :ingot,
  forge_client: ForgeMock,
  anvil_client: AnvilMock
```

## Development Workflow

### Local Development

1. Clone all three repos as siblings:
```
North-Shore-AI/
├── forge/
├── anvil/
└── ingot/
```

2. Start dependencies:
```bash
cd forge && iex -S mix
cd anvil && iex -S mix
```

3. Start Ingot:
```bash
cd ingot && mix phx.server
```

### Dependency Updates

When Forge/Anvil change:

```bash
cd ingot
mix deps.update forge anvil
mix deps.compile
mix test
```

### Version Pinning

For production, use git dependencies with version tags:

```elixir
{:forge, github: "North-Shore-AI/forge", tag: "v1.0.0"},
{:anvil, github: "North-Shore-AI/anvil", tag: "v1.0.0"}
```

## API Contracts

### Forge Expected API

```elixir
@callback fetch_next(user_id :: String.t()) ::
  {:ok, sample()} | {:error, :queue_empty} | {:error, term()}

@callback skip(sample_id :: String.t(), user_id :: String.t()) ::
  :ok | {:error, term()}

@callback stats() ::
  %{
    total: integer(),
    completed: integer(),
    remaining: integer()
  }
```

### Anvil Expected API

```elixir
@callback store(label :: map()) ::
  {:ok, label()} | {:error, term()}

@callback count() :: integer()

@callback for_session(session_id :: String.t()) :: list(label())

@callback to_csv() :: {:ok, String.t()} | {:error, term()}
```

## Versioning Strategy

### Semantic Versioning

All three libraries follow SemVer:

- **Major**: Breaking API changes
- **Minor**: New features, backward compatible
- **Patch**: Bug fixes

### Compatibility Matrix

| Ingot | Forge | Anvil |
|-------|-------|-------|
| 0.1.x | 0.1.x | 0.1.x |
| 0.2.x | 0.1.x | 0.1.x |
| 1.0.x | 1.0.x | 1.0.x |

### Breaking Change Protocol

If Forge or Anvil introduce breaking changes:

1. Update Ingot client modules
2. Update tests
3. Bump Ingot version accordingly
4. Document migration in CHANGELOG

## Alternatives Considered

### 1. Monolithic Application

Implement all functionality in one application.

**Rejected because:**
- Poor separation of concerns
- Harder to test
- Less reusable
- See ADR-001

### 2. HTTP API Integration

Access Forge and Anvil via HTTP APIs.

**Rejected because:**
- Adds latency
- More complex deployment
- Network overhead
- Unnecessary for local dependencies

### 3. Direct Database Access

Have Ingot directly query Forge/Anvil databases.

**Rejected because:**
- Violates encapsulation
- Tight coupling
- Bypasses business logic
- Fragile to schema changes

### 4. Message Queue Integration

Use message queue (RabbitMQ, Kafka) between libraries.

**Rejected because:**
- Overkill for local dependencies
- Adds operational complexity
- Introduces latency
- Not needed for initial version

## References

- [ADR-001: Thin Wrapper Architecture](001-thin-wrapper-architecture.md)
- [Mix Dependencies Documentation](https://hexdocs.pm/mix/Mix.Tasks.Deps.html)
- [Mox Testing Library](https://hexdocs.pm/mox/Mox.html)
