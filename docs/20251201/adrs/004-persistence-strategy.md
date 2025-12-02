# ADR-004: Persistence Strategy

## Status
Accepted

## Context

The North-Shore-AI ecosystem consists of multiple Elixir applications, each with specific persistence needs:

- **Forge**: Stores pipelines, samples, measurements, artifacts (blob references), execution metadata
- **Anvil**: Stores queues, assignments, labels, schema versions, audit logs, user roles
- **Ingot**: UI layer requiring minimal persistence (auth sessions, UI preferences)
- **CNS**: Dialectical reasoning experiments generating samples consumed by Ingot labelers

**Current State:**
- Each repo can independently provision Postgres databases
- No standardized approach to shared persistence
- Risk of data sprawl: samples duplicated, inconsistent labeling metadata
- Lineage tracking across systems is manual (matching sample_id strings)

**Persistence Requirements:**

1. **Sample Lineage**: From Forge sample_id → Anvil label → Crucible dataset export, full provenance must be queryable
2. **Concurrent Access**: Multiple Ingot web nodes, Anvil workers, Forge pipelines accessing same data
3. **Blob Storage**: Images, audio, JSON artifacts (potentially GBs per sample) stored separately from metadata
4. **Schema Evolution**: Label schemas change (add dimensions, validation rules) without breaking existing labels
5. **Multi-Tenancy**: Future requirement to isolate different research groups or external clients
6. **Backup & Recovery**: Point-in-time restore for compliance, disaster recovery

**Key Questions:**

1. Should each repo have its own Postgres instance, or share a cluster?
2. How to handle blob storage (S3, MinIO, local filesystem)?
3. Should Ingot persist any domain data, or remain purely stateless?
4. How to enforce foreign key relationships across service boundaries (e.g., Anvil references Forge samples)?
5. What level of database normalization (3NF vs denormalized for performance)?

## Decision

**Use a single Postgres cluster with separate schemas for Forge, Anvil, and optional Ingot auth. Blob storage via shared MinIO/S3 with signed URLs. No per-repo database instances. Ingot remains stateless (no domain data persistence), optionally storing minimal auth/session data if not using external IdP.**

### Architecture

```
┌────────────────────────────────────────────────────┐
│          Single Postgres Cluster (v14+)            │
│  ┌──────────────────────────────────────────────┐  │
│  │         Schema: forge                        │  │
│  │  - pipelines                                 │  │
│  │  - samples (id, pipeline_id, payload, ...)  │  │
│  │  - measurements (sample_id, key, value)     │  │
│  │  - artifacts (sample_id, storage_key, ...)  │  │
│  │  - pipeline_runs (metadata, telemetry)      │  │
│  └──────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────┐  │
│  │         Schema: anvil                        │  │
│  │  - queues (id, label_schema, policy, ...)   │  │
│  │  - assignments (queue_id, sample_id, ...)   │  │
│  │  - labels (assignment_id, labeler_id, ...)  │  │
│  │  - users (id, external_id, email, ...)      │  │
│  │  - user_roles (user_id, role, scope)        │  │
│  │  - queue_access (queue_id, user_id, ...)    │  │
│  │  - schema_versions (queue_id, version, ...) │  │
│  │  - audit_log (event, user_id, metadata)     │  │
│  └──────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────┐  │
│  │  Schema: ingot (optional, if not using IdP) │  │
│  │  - users (id, external_id, email, ...)      │  │
│  │  - sessions (token, user_id, expires_at)    │  │
│  │  - ui_preferences (user_id, settings)       │  │
│  └──────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────┘

┌────────────────────────────────────────────────────┐
│       Blob Storage (MinIO / S3 / R2)               │
│  Buckets:                                          │
│  - forge-artifacts (samples/sample_123/image.png)  │
│  - anvil-exports (queues/queue_456/labels.jsonl)   │
│  - cns-narratives (runs/run_789/synthesis.json)    │
└────────────────────────────────────────────────────┘
```

### Database Configuration

**Connection Pooling:**

```elixir
# config/runtime.exs
config :forge, Forge.Repo,
  url: database_url(),
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "10")),
  queue_target: 50,
  queue_interval: 1000,
  schema: "forge",
  migration_primary_key: [type: :uuid]

config :anvil, Anvil.Repo,
  url: database_url(),
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "10")),
  schema: "anvil",
  migration_primary_key: [type: :uuid]

# Optional: Ingot auth repo
config :ingot, Ingot.Repo,
  url: database_url(),
  pool_size: 5,  # Lower pool, minimal usage
  schema: "ingot",
  migration_primary_key: [type: :uuid]

defp database_url do
  System.get_env("DATABASE_URL") ||
    "ecto://postgres:postgres@localhost/nsai_research"
end
```

**Single Cluster, Multiple Schemas:**

```sql
-- Run once on cluster setup
CREATE DATABASE nsai_research;

\c nsai_research

CREATE SCHEMA forge;
CREATE SCHEMA anvil;
CREATE SCHEMA ingot;  -- Optional

-- Grant permissions per application
CREATE ROLE forge_app WITH LOGIN PASSWORD 'forge_secret';
GRANT USAGE, CREATE ON SCHEMA forge TO forge_app;
GRANT SELECT ON ALL TABLES IN SCHEMA anvil TO forge_app;  -- Read-only to Anvil

CREATE ROLE anvil_app WITH LOGIN PASSWORD 'anvil_secret';
GRANT USAGE, CREATE ON SCHEMA anvil TO anvil_app;
GRANT SELECT ON ALL TABLES IN SCHEMA forge TO anvil_app;  -- Read-only to Forge

CREATE ROLE ingot_app WITH LOGIN PASSWORD 'ingot_secret';
GRANT USAGE ON SCHEMA ingot TO ingot_app;  -- Optional
GRANT SELECT ON ALL TABLES IN SCHEMA forge, anvil TO ingot_app;  -- Read-only
```

**Why Single Cluster:**

1. **Referential Integrity**: Anvil assignments reference Forge samples via `sample_id`. With shared DB, can use foreign keys or at least validate existence in DB constraints.
   ```sql
   -- anvil.assignments
   CREATE TABLE anvil.assignments (
     id UUID PRIMARY KEY,
     sample_id UUID NOT NULL,
     -- Foreign key would require cross-schema references (Postgres supports this)
     -- FOREIGN KEY (sample_id) REFERENCES forge.samples(id),
     -- Alternative: application-level validation via AnvilClient → ForgeClient
     ...
   );
   ```

2. **Lineage Queries**: Admins can join across schemas for reporting:
   ```sql
   -- "Show all labels for samples from pipeline X"
   SELECT
     f.samples.id,
     f.samples.payload->>'claim_id',
     a.labels.label_data,
     a.labels.labeler_id
   FROM forge.samples f
   JOIN anvil.assignments asg ON asg.sample_id = f.id
   JOIN anvil.labels a ON a.assignment_id = asg.id
   WHERE f.pipeline_id = 'pipeline_cns_synthesis';
   ```

3. **Simplified Ops**: One backup schedule, one connection string, one monitoring dashboard. No cross-database sync.

4. **Cost Efficiency**: For research deployments, single Postgres instance (e.g., RDS db.t3.medium) handles combined load. No need for separate instances.

**When to Split:**

- Multi-tenant SaaS with strong isolation requirements → separate databases per tenant
- Very high write volume (>10K samples/sec) → shard Forge by pipeline_id
- Compliance requirements (e.g., PII in Anvil must be in separate encrypted volume) → separate instances

For current NSAI research use case, single cluster suffices.

### Blob Storage Strategy

**MinIO/S3 Buckets:**

- **forge-artifacts**: Sample artifacts (images, audio, JSON payloads)
  - Path: `samples/{sample_id}/{artifact_id}.{ext}`
  - Example: `samples/550e8400-e29b-41d4-a716-446655440000/image_001.png`

- **anvil-exports**: Label exports triggered by admins
  - Path: `queues/{queue_id}/exports/{timestamp}.{format}`
  - Example: `queues/queue_cns_coherence/exports/2025-12-01T10:30:00Z.jsonl`

- **cns-narratives**: CNS-specific large artifacts (full synthesis results)
  - Path: `runs/{run_id}/narratives/{narrative_id}.json`

**Access Pattern:**

```elixir
# Forge stores artifact, returns reference
{:ok, artifact} = Forge.Artifacts.create(%{
  sample_id: sample_id,
  storage_key: "samples/#{sample_id}/image.png",
  artifact_type: :image,
  content_type: "image/png"
})

# Upload to S3
ExAws.S3.put_object("forge-artifacts", artifact.storage_key, image_binary)
|> ExAws.request()

# Ingot fetches via signed URL (temporary, expires in 1 hour)
defmodule Forge.Storage do
  def signed_url(storage_key, expires_in_seconds \\ 3600) do
    ExAws.S3.presigned_url(
      ExAws.Config.new(:s3),
      :get,
      "forge-artifacts",
      storage_key,
      expires_in: expires_in_seconds
    )
  end
end

# In ForgeClient DTO
defp to_artifact_dto(%Forge.Artifact{} = artifact) do
  %DTO.Artifact{
    id: artifact.id,
    url: Forge.Storage.signed_url(artifact.storage_key),  # Signed URL
    filename: artifact.filename,
    ...
  }
end
```

**Why Not Database BLOBs:**

- **Performance**: Storing multi-MB images in Postgres bloats tables, slows backups
- **Scalability**: S3/MinIO auto-scales, CDN-friendly (CloudFront/Cloudflare)
- **Cost**: S3 cheaper than provisioned Postgres storage
- **Streaming**: S3 supports range requests, partial downloads

**Local Development:**

```yaml
# docker-compose.yml
services:
  postgres:
    image: postgres:14
    environment:
      POSTGRES_DB: nsai_research
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"

  minio:
    image: minio/minio
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: minioadmin
      MINIO_ROOT_PASSWORD: minioadmin
    ports:
      - "9000:9000"
      - "9001:9001"
    volumes:
      - minio_data:/data

volumes:
  minio_data:
```

### Schema Versioning (Anvil)

Label schemas evolve (add dimensions, change validation). Anvil tracks versions to handle historical labels:

```elixir
# anvil.schema_versions
defmodule Anvil.SchemaVersion do
  schema "schema_versions" do
    field :queue_id, :string
    field :version, :integer
    field :schema_def, :map  # JSON schema for label validation
    field :active, :boolean, default: true
    timestamps()
  end
end

# Example schema evolution
# v1: %{coherence: 1..5, notes: string}
# v2: %{coherence: 1..5, groundedness: 1..5, notes: string}

# Historical labels reference schema version
# anvil.labels
CREATE TABLE anvil.labels (
  id UUID PRIMARY KEY,
  assignment_id UUID NOT NULL,
  schema_version_id UUID NOT NULL,
  label_data JSONB NOT NULL,  -- Validated against schema_version_id
  ...
);
```

When Ingot displays labels, it fetches the schema version for correct rendering.

### Ingot Persistence (Minimal)

**Option 1: No Ingot Repo (Fully Stateless)**

- Auth via OIDC, no local user storage
- Sessions in signed cookies (Phoenix default)
- UI preferences in browser localStorage

**Option 2: Minimal Ingot Repo (Recommended)**

```elixir
# ingot.users (minimal auth cache)
CREATE TABLE ingot.users (
  id UUID PRIMARY KEY,
  external_id TEXT UNIQUE,  -- from OIDC sub claim
  email TEXT UNIQUE,
  created_at TIMESTAMP DEFAULT NOW()
);

# ingot.sessions (optional, for server-side revocation)
CREATE TABLE ingot.sessions (
  token TEXT PRIMARY KEY,
  user_id UUID REFERENCES ingot.users(id),
  expires_at TIMESTAMP NOT NULL,
  revoked_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);

# ingot.ui_preferences (optional, server-side sync)
CREATE TABLE ingot.ui_preferences (
  user_id UUID PRIMARY KEY REFERENCES ingot.users(id),
  settings JSONB NOT NULL,  -- {theme: "dark", shortcuts: {...}}
  updated_at TIMESTAMP DEFAULT NOW()
);
```

**Trade-off:** Option 1 is simpler (no migrations, no backups). Option 2 enables session revocation and cross-device UI sync. For CNS use case, Option 1 suffices.

### Migration Management

Each app manages its own schema migrations:

```bash
# Forge migrations
cd forge
mix ecto.create  # Creates database if needed
mix ecto.migrate

# Anvil migrations
cd anvil
mix ecto.migrate

# Ingot migrations (if using Ingot.Repo)
cd ingot
mix ecto.migrate
```

**Shared Database, Independent Migrations:**

- Forge migrations in `priv/repo/migrations` modify `forge.*` tables
- Anvil migrations modify `anvil.*` tables
- No conflicts as long as schema namespaces are respected

**Cross-Schema References:**

```elixir
# In Anvil migration (if using FK across schemas)
def change do
  create table(:assignments, primary_key: false) do
    add :id, :uuid, primary key: true
    add :sample_id, references("forge.samples", type: :uuid, on_delete: :restrict)
    ...
  end
end
```

However, **avoid hard FK constraints across service boundaries** (violates service isolation). Instead, use application-level validation:

```elixir
# In Anvil.Assignments.create/1
def create(attrs) do
  with {:ok, sample} <- ForgeClient.get_sample(attrs.sample_id) do
    %Assignment{}
    |> changeset(attrs)
    |> Repo.insert()
  else
    {:error, :not_found} -> {:error, "Sample not found"}
  end
end
```

### Backup & Recovery

**Postgres:**

```bash
# Daily backups via pg_dump
pg_dump -h localhost -U postgres -F c -b -v \
  -f /backups/nsai_research_$(date +%Y%m%d).dump \
  nsai_research

# Restore
pg_restore -h localhost -U postgres -d nsai_research \
  /backups/nsai_research_20251201.dump
```

**Managed Solutions:**

- **AWS RDS**: Automated daily snapshots, point-in-time recovery
- **Supabase**: Automatic backups, 7-day retention
- **Render**: Daily backups on paid plans

**S3/MinIO:**

- Enable versioning on buckets (keep previous versions of artifacts)
- Lifecycle policies: move old exports to Glacier after 90 days
- Cross-region replication for disaster recovery

## Consequences

### Positive

- **Single Source of Truth**: One database for all research data. No synchronization bugs between Forge/Anvil instances.

- **Simplified Lineage**: Queries spanning samples → labels → exports are simple SQL joins. Debugging "which pipeline produced this labeled sample?" is straightforward.

- **Operational Simplicity**: One connection string, one backup schedule, one monitoring dashboard. Reduces cognitive load for SRE.

- **Cost Efficiency**: Research workloads fit in single Postgres instance (RDS db.t3.large: ~$100/month). Separate instances would 3x cost.

- **Development Velocity**: Local development with `docker-compose` provides full stack (Postgres + MinIO). No need to mock S3 or run multiple DBs.

- **Blob Scalability**: S3/MinIO scales independently of database. Large CNS narratives (10MB JSON) don't bloat Postgres.

### Negative

- **Coupling Risk**: If all apps connect to same DB, schema changes in Forge could theoretically break Anvil.
  - *Mitigation*: Separate schemas (`forge.*`, `anvil.*`) enforce logical isolation. Ecto migrations are app-scoped.
  - *Mitigation*: Read-only cross-schema access (Anvil can read `forge.samples`, not modify).

- **Single Point of Failure**: If Postgres is down, all services are unavailable.
  - *Mitigation*: Use managed Postgres (RDS/Supabase) with multi-AZ, automated failover.
  - *Mitigation*: Circuit breakers in clients degrade gracefully (e.g., Ingot shows cached data).

- **Connection Pool Contention**: Multiple apps sharing same cluster could exhaust connections.
  - *Mitigation*: Size pools appropriately (Forge: 10, Anvil: 10, Ingot: 5 = 25 total). Postgres default max_connections=100.
  - *Mitigation*: Use PgBouncer for connection pooling if needed.

- **Cross-Schema FK Complexity**: Foreign keys across schemas work but complicate rollback scenarios.
  - *Mitigation*: Avoid hard FKs. Use application-level validation (AnvilClient checks ForgeClient before creating assignment).

- **Multi-Tenancy Complexity**: Shared database requires row-level security (RLS) for tenant isolation. Separate databases are cleaner.
  - *Mitigation*: For NSAI research (single-tenant), not a concern. If multi-tenancy needed, migrate to per-tenant databases.

### Neutral

- **Schema Migrations Order**: Forge must migrate before Anvil if Anvil references Forge tables (even read-only).
  - *Mitigation*: Document migration order in deployment guide. Consider shared migration orchestration tool.

- **Backup Size**: Single database backup includes all schemas. Larger backup files, longer restore times.
  - *Mitigation*: Selective restore (pg_restore can restore specific schemas). For disaster recovery, restore all.

- **Read Replicas**: For analytics queries (e.g., "aggregate labels across all queues"), use read replica to avoid impacting production writes.
  - *Mitigation*: Anvil and Forge can configure read replicas for heavy queries.

## Implementation Checklist

1. Provision Postgres cluster (RDS/Supabase/local Docker)
2. Create schemas: `forge`, `anvil`, `ingot` (if needed)
3. Configure Ecto repos with `schema: "forge"` option
4. Create application-specific DB users with appropriate grants
5. Provision MinIO/S3 buckets: `forge-artifacts`, `anvil-exports`
6. Configure ExAws for S3 access (credentials, region)
7. Update Forge.Storage to use signed URLs
8. Update AnvilClient to validate sample existence via ForgeClient
9. Document migration order (Forge → Anvil → Ingot)
10. Set up backup automation (pg_dump daily, S3 versioning)
11. Configure monitoring (connection pool metrics, query latency)
12. Write runbook for disaster recovery (restore from backup)

## Database Schema Examples

### Forge Schema (Simplified)

```sql
CREATE SCHEMA forge;

CREATE TABLE forge.pipelines (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  config JSONB NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE forge.samples (
  id UUID PRIMARY KEY,
  pipeline_id UUID NOT NULL REFERENCES forge.pipelines(id),
  payload JSONB NOT NULL,
  metadata JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE forge.artifacts (
  id UUID PRIMARY KEY,
  sample_id UUID NOT NULL REFERENCES forge.samples(id),
  storage_key TEXT NOT NULL,  -- S3 key
  artifact_type TEXT NOT NULL,
  content_type TEXT,
  size_bytes BIGINT,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_samples_pipeline ON forge.samples(pipeline_id);
CREATE INDEX idx_artifacts_sample ON forge.artifacts(sample_id);
```

### Anvil Schema (Simplified)

```sql
CREATE SCHEMA anvil;

CREATE TABLE anvil.queues (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  label_schema JSONB NOT NULL,
  policy JSONB,  -- {redundancy: 3, expertise_weighting: true}
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE anvil.assignments (
  id UUID PRIMARY KEY,
  queue_id UUID NOT NULL REFERENCES anvil.queues(id),
  sample_id UUID NOT NULL,  -- References forge.samples(id), no FK
  labeler_id UUID,
  assigned_at TIMESTAMP,
  completed_at TIMESTAMP,
  status TEXT CHECK (status IN ('pending', 'assigned', 'completed', 'skipped'))
);

CREATE TABLE anvil.labels (
  id UUID PRIMARY KEY,
  assignment_id UUID NOT NULL REFERENCES anvil.assignments(id),
  schema_version_id UUID NOT NULL,
  label_data JSONB NOT NULL,
  submitted_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_assignments_queue ON anvil.assignments(queue_id);
CREATE INDEX idx_assignments_sample ON anvil.assignments(sample_id);
CREATE INDEX idx_labels_assignment ON anvil.labels(assignment_id);
```

## Related ADRs

- ADR-001: Stateless UI Architecture (Ingot has minimal persistence)
- ADR-002: Client Layer Design (application-level FK validation)
- ADR-003: Auth Strategy (optional Ingot.Repo for sessions)
- ADR-009: Deployment & Packaging (DATABASE_URL configuration)
