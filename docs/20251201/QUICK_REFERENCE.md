# Ingot Architecture Quick Reference

**One-page cheat sheet for Ingot's architectural decisions**

## Core Principle: Stateless UI Layer

```
Ingot (Phoenix LiveView UI)
    ↓ delegates to
Forge (Sample Factory) + Anvil (Labeling Queue)
```

Ingot does NOT store:
- ❌ Samples
- ❌ Labels
- ❌ Pipelines
- ❌ Queue definitions

Ingot ONLY stores:
- ✓ Optional auth sessions (if not using OIDC)
- ✓ UI preferences (in-session, ephemeral)

## Key Components

### 1. Client Layer (ADR-002)
```elixir
# Read sample from Forge
{:ok, sample} = Ingot.ForgeClient.get_sample(sample_id)

# Submit label to Anvil
:ok = Ingot.AnvilClient.submit_label(assignment_id, label_data)

# Adapters: ElixirAdapter (in-cluster) or HTTPAdapter (remote)
```

### 2. Authentication (ADR-003)
```
Internal Users → OIDC (Google/Keycloak) → Session
External Labelers → Invite Code → Limited Session

Roles (stored in Anvil):
- admin: full control
- labeler: label assignments only
- auditor: read-only access
- adjudicator: resolve disagreements
```

### 3. Real-Time Updates (ADR-005)
```
Forge/Anvil :telemetry events
    → Ingot.TelemetryHandler
    → Phoenix.PubSub
    → LiveView processes
    → WebSocket → Browser
```

### 4. Pluggable Components (ADR-007)
```elixir
# Queue config specifies component
queue.metadata = %{component_module: "CNS.IngotComponents"}

# Component implements behaviors
@behaviour Ingot.SampleRenderer
@behaviour Ingot.LabelFormRenderer

# Default fallback for generic samples
Ingot.DefaultComponent
```

## Data Flow

### Labeling Workflow
```
1. Labeler visits /queue/:id
2. LabelingLive mounts
   → AnvilClient.get_next_assignment(queue_id, user_id)
   → ForgeClient.get_sample(sample_id)
3. Labeler completes form, clicks Submit
   → Optimistic UI: show next assignment immediately
   → Background: AnvilClient.submit_label(assignment_id, data)
   → If success: continue
   → If error: revert, show error
4. Repeat from step 3
```

### Admin Dashboard Workflow
```
1. Admin visits /admin/dashboard
2. AdminDashboardLive mounts
   → AnvilClient.list_queues()
   → For each queue: AnvilClient.get_queue_stats(queue_id)
3. Subscribe to PubSub: "admin:global"
4. Real-time updates:
   {:queue_stats_updated, queue_id, new_stats}
   → Update assigns, LiveView re-renders
```

## Configuration (ENV vars)

```bash
# Required
DATABASE_URL=ecto://user:pass@host/db
SECRET_KEY_BASE=<64-char-hex>

# Forge/Anvil endpoints
FORGE_ADAPTER=elixir  # or http
FORGE_URL=http://forge.svc.cluster.local:4001
ANVIL_ADAPTER=elixir
ANVIL_URL=http://anvil.svc.cluster.local:4002

# OIDC (optional, for auth)
OIDC_PROVIDER=https://auth.nsai.io
OIDC_CLIENT_ID=ingot
OIDC_CLIENT_SECRET=secret

# S3 (for artifact URLs)
AWS_ACCESS_KEY_ID=key
AWS_SECRET_ACCESS_KEY=secret
AWS_REGION=us-east-1

# Phoenix
PHX_HOST=ingot.nsai.io
PORT=4000
```

## Deployment

### Docker Build
```bash
docker build -t gcr.io/nsai/ingot:v1.0.0 .
docker push gcr.io/nsai/ingot:v1.0.0
```

### Kubernetes Deploy
```bash
kubectl set image deployment/ingot ingot=gcr.io/nsai/ingot:v1.0.0 -n research
kubectl rollout status deployment/ingot -n research
```

### Health Check
```bash
curl https://ingot.nsai.io/health
# {"status":"ok","services":{"forge":{"status":"healthy"},"anvil":{"status":"healthy"}}}
```

## Key Patterns

### 1. Client Error Handling
```elixir
case ForgeClient.get_sample(sample_id) do
  {:ok, sample} -> {:ok, assign(socket, sample: sample)}
  {:error, :not_found} -> {:ok, redirect(socket, to: ~p"/error")}
  {:error, :timeout} -> {:ok, put_flash(socket, :error, "Slow network")}
end
```

### 2. Optimistic UI
```elixir
# Show result immediately
socket = assign(socket, assignment: next_assignment)

# Submit in background
Task.async(fn -> AnvilClient.submit_label(...) end)

# Handle error later
def handle_info({:submit_error, reason}, socket) do
  # Revert optimistic update
end
```

### 3. Component Registration
```elixir
# Queue metadata (in Anvil)
%{component_module: "CNS.IngotComponents"}

# Ingot loads dynamically
{:ok, component} = ComponentRegistry.get_component(queue_id)

# Render sample
component.render_sample(sample, mode: :labeling)
```

### 4. Telemetry
```elixir
# Emit event
:telemetry.execute(
  [:ingot, :label, :submit],
  %{duration_ms: 245},
  %{queue_id: queue_id, user_id: user_id}
)

# Handler converts to PubSub + Prometheus
```

## Database Schemas

```sql
-- Shared Postgres cluster

-- forge schema
forge.pipelines
forge.samples
forge.artifacts

-- anvil schema
anvil.queues
anvil.assignments
anvil.labels
anvil.users
anvil.user_roles

-- ingot schema (optional)
ingot.users
ingot.sessions
```

## Security Checklist

- ✓ OIDC authentication (no passwords in Ingot)
- ✓ Role-based access (enforced in router plugs)
- ✓ CSP headers (prevent XSS)
- ✓ HTTPS enforcement (production)
- ✓ Secure session cookies (signed, encrypted)
- ✓ Secrets via ENV vars (not committed)
- ✓ Signed S3 URLs (artifacts expire in 1 hour)

## Performance Targets

- **Latency**: p95 label submit <500ms
- **Throughput**: 100+ concurrent labelers per node
- **Availability**: 99.9% uptime
- **Scalability**: Horizontal (add more pods)

## Common Operations

### Create Queue
```elixir
AnvilClient.create_queue(%{
  name: "CNS Coherence",
  label_schema: %{dimensions: [...]},
  metadata: %{component_module: "CNS.IngotComponents"}
})
```

### Trigger Export
```elixir
AnvilClient.trigger_export(queue_id, :jsonl)
# Returns: {:ok, job_id}
```

### View Logs
```bash
kubectl logs -f deployment/ingot -n research
# JSON logs: {"level":"info","message":"Label submitted","queue_id":"..."}
```

### Scale Deployment
```bash
kubectl scale deployment/ingot --replicas=5 -n research
```

## Troubleshooting

### High Latency
1. Check Prometheus: `ingot_anvil_client_duration_seconds`
2. Check traces: distributed tracing via Foundation/AITrace
3. Check database: slow queries in Anvil Postgres

### Failed Submissions
1. Check Ingot logs: search for "submit_label" errors
2. Check Anvil health: `curl http://anvil:4002/health`
3. Check network: connectivity Ingot → Anvil

### Memory Issues
1. Check LiveView process count: too many active sessions?
2. Check PubSub: high broadcast volume?
3. Scale horizontally: add more pods

## ADR Reference

| ADR | Topic | Key Decision |
|-----|-------|--------------|
| 001 | Architecture | Stateless UI, no domain data |
| 002 | Clients | ForgeClient + AnvilClient behaviors |
| 003 | Auth | OIDC + invite codes |
| 004 | Persistence | Shared Postgres, MinIO/S3 |
| 005 | UX | LiveView + PubSub, optimistic UI |
| 006 | Admin | Dashboards, adjudication, exports |
| 007 | Components | Pluggable behaviors, CNS example |
| 008 | Telemetry | Prometheus, tracing, logging |
| 009 | Deployment | Docker, K8s, ENV config |
| 010 | Offline | Online-only, future PWA |

## External Links

- [Full ADR Directory](/home/home/p/g/North-Shore-AI/ingot/docs/20251201/adrs/)
- [Buildout Plan](/home/home/p/g/North-Shore-AI/docs/20251201/ingot.md)
- [Phoenix LiveView Docs](https://hexdocs.pm/phoenix_live_view)
- [Ecto Docs](https://hexdocs.pm/ecto)

---

**For detailed information, refer to individual ADRs.**
**This is a summary only - not a replacement for comprehensive documentation.**
