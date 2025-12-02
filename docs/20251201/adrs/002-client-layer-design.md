# ADR-002: Client Layer Design

## Status
Accepted

## Context

Per ADR-001, Ingot operates as a stateless UI layer communicating with Forge and Anvil for all domain operations. The boundary between Ingot and these services is critical for:

1. **API Stability**: Forge and Anvil internal structs may evolve independently; Ingot should not break on internal refactors
2. **Error Handling**: Network failures, timeouts, service degradation, and business logic errors must be surfaced consistently
3. **Deployment Flexibility**: Ingot may be deployed in-cluster (direct Elixir calls) or as separate service (HTTP/GRPC)
4. **Testing**: Client layer must be mockable for LiveView tests without running full Forge/Anvil instances
5. **Circuit Breaking**: Repeated failures to upstream services should trigger protective measures

**Current State (v0.1):**
- Optional dependencies on `forge_ex` and `anvil_ex` (application modules)
- Direct function calls with inconsistent error handling
- No retry logic or circuit breakers
- Tight coupling to internal structs

**Key Questions:**
- Should clients use behavior contracts for swappable implementations?
- How should DTOs differ from internal domain structs?
- When should retries happen vs fail-fast?
- How to handle paginated results and streaming?

## Decision

**Implement dedicated `Ingot.ForgeClient` and `Ingot.AnvilClient` modules with behavior contracts, DTO translation layer, and resilience patterns (retries, circuit breakers, timeouts).**

### Architecture

```
┌─────────────────────────────────────────────────┐
│                 LiveView Layer                  │
│  (LabelingLive, AdminDashboard, QueueExplorer)  │
└────────────┬────────────────────┬───────────────┘
             │                    │
             ▼                    ▼
    ┌────────────────┐   ┌────────────────┐
    │  ForgeClient   │   │  AnvilClient   │
    │   (Behavior)   │   │   (Behavior)   │
    └────────┬───────┘   └────────┬───────┘
             │                    │
    ┌────────▼───────┐   ┌────────▼───────┐
    │ ForgeClient    │   │ AnvilClient    │
    │ .ElixirAdapter │   │ .ElixirAdapter │
    └────────┬───────┘   └────────┬───────┘
             │                    │
             ▼                    ▼
      ┌──────────┐          ┌──────────┐
      │  Forge   │          │  Anvil   │
      │  (App)   │          │  (App)   │
      └──────────┘          └──────────┘

Alternative Adapters (future):
- ForgeClient.HTTPAdapter
- AnvilClient.GRPCAdapter
```

### Client Behaviors

#### ForgeClient Behavior

```elixir
defmodule Ingot.ForgeClient do
  @moduledoc """
  Behavior for fetching samples and artifacts from Forge.
  Ingot uses read-only operations; no sample creation/mutation.
  """

  alias Ingot.DTO.{Sample, Pipeline, Artifact}

  @type sample_id :: String.t()
  @type pipeline_id :: String.t()
  @type error :: :not_found | :timeout | :network | :unauthorized | {:unexpected, term()}

  @callback get_sample(sample_id) ::
    {:ok, Sample.t()} | {:error, error}

  @callback get_artifacts(sample_id) ::
    {:ok, [Artifact.t()]} | {:error, error}

  @callback get_pipeline(pipeline_id) ::
    {:ok, Pipeline.t()} | {:error, error}

  @callback stream_batch(pipeline_id, opts :: Keyword.t()) ::
    {:ok, Enumerable.t(Sample.t())} | {:error, error}

  @callback get_measurements(sample_id) ::
    {:ok, map()} | {:error, error}

  # Delegate to configured adapter
  def get_sample(sample_id), do: adapter().get_sample(sample_id)
  def get_artifacts(sample_id), do: adapter().get_artifacts(sample_id)
  def get_pipeline(pipeline_id), do: adapter().get_pipeline(pipeline_id)
  def stream_batch(pipeline_id, opts \\ []), do: adapter().stream_batch(pipeline_id, opts)
  def get_measurements(sample_id), do: adapter().get_measurements(sample_id)

  defp adapter do
    Application.get_env(:ingot, :forge_client_adapter, Ingot.ForgeClient.ElixirAdapter)
  end
end
```

#### AnvilClient Behavior

```elixir
defmodule Ingot.AnvilClient do
  @moduledoc """
  Behavior for labeling operations via Anvil.
  Handles queue subscriptions, assignment fetching, label submission, and stats.
  """

  alias Ingot.DTO.{Queue, Assignment, Label, AgreementStats, UserRole}

  @type queue_id :: String.t()
  @type assignment_id :: String.t()
  @type user_id :: String.t()
  @type error :: :not_found | :no_assignments | :duplicate_label | :timeout | :network | {:validation, map()} | {:unexpected, term()}

  @callback get_queue(queue_id) ::
    {:ok, Queue.t()} | {:error, error}

  @callback get_next_assignment(queue_id, user_id, opts :: Keyword.t()) ::
    {:ok, Assignment.t()} | {:error, error}

  @callback submit_label(assignment_id, label_data :: map()) ::
    :ok | {:error, error}

  @callback get_assignment(assignment_id) ::
    {:ok, Assignment.t()} | {:error, error}

  @callback get_queue_stats(queue_id) ::
    {:ok, AgreementStats.t()} | {:error, error}

  @callback get_user_roles(user_id) ::
    {:ok, [UserRole.t()]} | {:error, error}

  @callback get_label_history(sample_id :: String.t()) ::
    {:ok, [Label.t()]} | {:error, error}

  @callback trigger_export(queue_id, format :: atom()) ::
    {:ok, job_id :: String.t()} | {:error, error}

  # Delegate to configured adapter
  def get_queue(queue_id), do: adapter().get_queue(queue_id)
  def get_next_assignment(queue_id, user_id, opts \\ []), do: adapter().get_next_assignment(queue_id, user_id, opts)
  def submit_label(assignment_id, label_data), do: adapter().submit_label(assignment_id, label_data)
  def get_assignment(assignment_id), do: adapter().get_assignment(assignment_id)
  def get_queue_stats(queue_id), do: adapter().get_queue_stats(queue_id)
  def get_user_roles(user_id), do: adapter().get_user_roles(user_id)
  def get_label_history(sample_id), do: adapter().get_label_history(sample_id)
  def trigger_export(queue_id, format), do: adapter().trigger_export(queue_id, format)

  defp adapter do
    Application.get_env(:ingot, :anvil_client_adapter, Ingot.AnvilClient.ElixirAdapter)
  end
end
```

### DTO Layer

DTOs decouple UI from internal service schemas. They are optimized for rendering, not persistence.

```elixir
defmodule Ingot.DTO.Sample do
  @moduledoc "UI-friendly sample representation"

  @type t :: %__MODULE__{
    id: String.t(),
    pipeline_id: String.t(),
    payload: map(),              # JSON-serializable data
    artifacts: [Artifact.t()],   # Embedded for convenience
    metadata: map(),             # Pipeline tags, run info
    created_at: DateTime.t()
  }

  defstruct [:id, :pipeline_id, :payload, :artifacts, :metadata, :created_at]
end

defmodule Ingot.DTO.Assignment do
  @moduledoc "Labeling task with context"

  @type t :: %__MODULE__{
    id: String.t(),
    queue_id: String.t(),
    sample: Sample.t(),          # Pre-fetched from Forge
    schema: map(),               # Label dimensions/validation
    existing_labels: [Label.t()], # For review/adjudication
    assigned_at: DateTime.t(),
    metadata: map()              # Queue policy hints
  }

  defstruct [:id, :queue_id, :sample, :schema, :existing_labels, :assigned_at, :metadata]
end

defmodule Ingot.DTO.Artifact do
  @moduledoc "File/blob reference with signed URL"

  @type t :: %__MODULE__{
    id: String.t(),
    sample_id: String.t(),
    artifact_type: atom(),  # :image, :audio, :video, :json, :binary
    url: String.t(),        # Signed S3 URL (expires)
    filename: String.t(),
    size_bytes: integer(),
    content_type: String.t()
  }

  defstruct [:id, :sample_id, :artifact_type, :url, :filename, :size_bytes, :content_type]
end
```

### Resilience Patterns

#### 1. Timeouts

All network calls have explicit timeouts:

```elixir
defmodule Ingot.ForgeClient.ElixirAdapter do
  @default_timeout 5_000  # 5 seconds

  def get_sample(sample_id) do
    case Task.await(
      Task.async(fn -> Forge.Samples.get(sample_id) end),
      timeout: config_timeout()
    ) do
      {:ok, sample} -> {:ok, to_dto(sample)}
      {:error, reason} -> {:error, normalize_error(reason)}
    catch
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end

  defp config_timeout do
    Application.get_env(:ingot, :forge_timeout, @default_timeout)
  end
end
```

#### 2. Retries with Backoff

Idempotent read operations retry on transient failures:

```elixir
defmodule Ingot.ClientHelper do
  @moduledoc "Shared resilience utilities"

  def retry(fun, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    backoff_ms = Keyword.get(opts, :backoff_ms, 100)

    retry_loop(fun, max_attempts, backoff_ms, 1)
  end

  defp retry_loop(fun, max_attempts, _backoff, attempt) when attempt > max_attempts do
    fun.()
  end

  defp retry_loop(fun, max_attempts, backoff_ms, attempt) do
    case fun.() do
      {:error, :timeout} = err when attempt < max_attempts ->
        :timer.sleep(backoff_ms * attempt)
        retry_loop(fun, max_attempts, backoff_ms, attempt + 1)

      {:error, :network} = err when attempt < max_attempts ->
        :timer.sleep(backoff_ms * attempt)
        retry_loop(fun, max_attempts, backoff_ms, attempt + 1)

      result ->
        result
    end
  end
end

# Usage in adapter
def get_sample(sample_id) do
  ClientHelper.retry(fn ->
    do_get_sample(sample_id)
  end, max_attempts: 3, backoff_ms: 200)
end
```

#### 3. Circuit Breaker

Prevent cascading failures when upstream services are consistently failing:

```elixir
defmodule Ingot.CircuitBreaker do
  use GenServer

  @moduledoc """
  Circuit breaker per service (forge, anvil).
  States: :closed (healthy), :open (failing), :half_open (testing recovery).
  """

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def call(breaker_name, fun) do
    case GenServer.call(breaker_name, :get_state) do
      :open ->
        {:error, :circuit_open}

      _ ->
        case fun.() do
          {:ok, _} = success ->
            GenServer.cast(breaker_name, :success)
            success

          {:error, _} = error ->
            GenServer.cast(breaker_name, :failure)
            error
        end
    end
  end

  # GenServer implementation tracks failure rate and auto-transitions states
  # (Implementation details omitted for brevity)
end

# Wrap client calls
def get_sample(sample_id) do
  CircuitBreaker.call(:forge_breaker, fn ->
    do_get_sample(sample_id)
  end)
end
```

### Adapter Implementations

#### Elixir Adapter (In-Cluster)

```elixir
defmodule Ingot.ForgeClient.ElixirAdapter do
  @behaviour Ingot.ForgeClient

  alias Ingot.DTO

  def get_sample(sample_id) do
    # Direct function call to Forge application
    case Forge.Samples.get(sample_id) do
      {:ok, sample} ->
        {:ok, to_sample_dto(sample)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, {:unexpected, reason}}
    end
  end

  defp to_sample_dto(%Forge.Sample{} = sample) do
    %DTO.Sample{
      id: sample.id,
      pipeline_id: sample.pipeline_id,
      payload: sample.payload,
      artifacts: Enum.map(sample.artifacts, &to_artifact_dto/1),
      metadata: sample.metadata,
      created_at: sample.inserted_at
    }
  end

  defp to_artifact_dto(%Forge.Artifact{} = artifact) do
    %DTO.Artifact{
      id: artifact.id,
      sample_id: artifact.sample_id,
      artifact_type: artifact.artifact_type,
      url: Forge.Storage.signed_url(artifact.storage_key),
      filename: artifact.filename,
      size_bytes: artifact.size_bytes,
      content_type: artifact.content_type
    }
  end
end
```

#### HTTP Adapter (Future)

```elixir
defmodule Ingot.ForgeClient.HTTPAdapter do
  @behaviour Ingot.ForgeClient

  def get_sample(sample_id) do
    base_url = Application.fetch_env!(:ingot, :forge_base_url)
    url = "#{base_url}/api/v1/samples/#{sample_id}"

    case HTTPoison.get(url, headers(), recv_timeout: 5_000) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, Jason.decode!(body, keys: :atoms) |> to_sample_dto()}

      {:ok, %{status_code: 404}} ->
        {:error, :not_found}

      {:ok, %{status_code: 401}} ->
        {:error, :unauthorized}

      {:error, %HTTPoison.Error{reason: :timeout}} ->
        {:error, :timeout}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, :network}
    end
  end

  defp headers do
    [
      {"Authorization", "Bearer #{api_token()}"},
      {"Content-Type", "application/json"}
    ]
  end
end
```

### Error Normalization

```elixir
defmodule Ingot.ClientHelper do
  @doc "Convert internal errors to standard client errors"
  def normalize_error(:not_found), do: :not_found
  def normalize_error(:unauthorized), do: :unauthorized
  def normalize_error({:timeout, _}), do: :timeout
  def normalize_error(%Ecto.Changeset{} = changeset) do
    {:validation, errors_from_changeset(changeset)}
  end
  def normalize_error(reason), do: {:unexpected, reason}
end
```

## Consequences

### Positive

- **Testability**: Mock adapters in tests without running services:
  ```elixir
  # test/support/mocks.ex
  defmodule Ingot.ForgeClient.MockAdapter do
    @behaviour Ingot.ForgeClient

    def get_sample("sample_123"), do: {:ok, %DTO.Sample{id: "sample_123", ...}}
    def get_sample(_), do: {:error, :not_found}
  end

  # config/test.exs
  config :ingot, forge_client_adapter: Ingot.ForgeClient.MockAdapter
  ```

- **Deployment Flexibility**: Swap adapters via config without code changes:
  ```elixir
  # config/prod.exs (in-cluster)
  config :ingot, forge_client_adapter: Ingot.ForgeClient.ElixirAdapter

  # config/prod_remote.exs (remote HTTP)
  config :ingot,
    forge_client_adapter: Ingot.ForgeClient.HTTPAdapter,
    forge_base_url: "https://forge.nsai.io"
  ```

- **API Stability**: Internal Forge/Anvil refactors only require adapter updates, not LiveView changes.

- **Resilience**: Retries, circuit breakers, and timeouts prevent cascading failures. UI remains responsive during transient outages.

- **Observable**: Client calls emit telemetry for monitoring:
  ```elixir
  :telemetry.execute(
    [:ingot, :forge_client, :get_sample],
    %{duration: duration_ms},
    %{sample_id: sample_id, result: :ok}
  )
  ```

### Negative

- **Latency Overhead**: DTO translation and adapter indirection add microseconds (negligible in practice, network dominates).

- **Maintenance Burden**: Multiple adapters require parallel updates when adding new operations.
  - *Mitigation*: Prefer Elixir adapter; only build HTTP/GRPC when needed.

- **Error Translation Complexity**: Mapping diverse internal errors to normalized client errors requires careful handling.
  - *Mitigation*: Comprehensive error normalization tests. Log original errors for debugging.

- **Streaming Complexity**: `stream_batch` requires adapter-specific pagination logic:
  ```elixir
  def stream_batch(pipeline_id, opts) do
    limit = Keyword.get(opts, :limit, 100)

    {:ok, Stream.resource(
      fn -> {0, true} end,  # {offset, has_more}
      fn {offset, true} ->
        case Forge.Samples.list(pipeline_id, offset: offset, limit: limit) do
          {:ok, samples} when length(samples) < limit ->
            {Enum.map(samples, &to_dto/1), {offset + limit, false}}
          {:ok, samples} ->
            {Enum.map(samples, &to_dto/1), {offset + limit, true}}
          {:error, _} ->
            {:halt, {offset, false}}
        end
      end,
      fn _ -> :ok end
    )}
  end
  ```

### Neutral

- **Adapter Selection**: Config-driven adapter choice works for most scenarios. Advanced routing (e.g., read from replica, write to primary) would require explicit client methods.

- **Caching Layer**: Clients don't implement caching (stateless principle). LiveView processes cache in assigns for session duration.

- **Authentication**: Adapters must handle auth tokens. Elixir adapter inherits process credentials. HTTP adapter uses bearer tokens from config.

## Implementation Checklist

1. Define `Ingot.ForgeClient` and `Ingot.AnvilClient` behaviors
2. Implement `Ingot.DTO.*` structs with translation helpers
3. Build `ElixirAdapter` for both clients with full DTO translation
4. Add timeout/retry/circuit-breaker wrappers in `Ingot.ClientHelper`
5. Emit telemetry events for all client operations
6. Write unit tests with mock adapters
7. Write integration tests against real Forge/Anvil instances
8. Document adapter config in README
9. (Future) Implement HTTP adapters when deploying separately

## Related ADRs

- ADR-001: Stateless UI Architecture (motivates client layer)
- ADR-004: Persistence Strategy (no Ingot-owned data)
- ADR-008: Telemetry & Observability (client telemetry events)
