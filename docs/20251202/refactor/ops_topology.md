# Ops & Topology Guide (Forge / Anvil / Ingot)

## Deploy shapes
- **Dev (single node)**: All three apps in one VM/container; SQLite or Postgres; MinIO; local auth; queue/component metadata kept simple.
- **Prod (separated)**: Forge pipelines (sample generation), Anvil (API/queues/labels), Ingot (UI). Shared Postgres and S3/MinIO. Auth via OIDC/JWT; per-tenant RBAC.
- **Airgap**: Same separation, no external APIs; local LLMs only; S3-compatible storage on-prem.

## Recommended defaults
- Postgres schemas per service or shared DB with schema names.
- S3/MinIO bucket for artifacts and exports.
- Feature flags: `ALLOW_DEFAULT_COMPONENT=true` to fall back gracefully.
- Auth: OIDC in Anvil; Ingot trusts session token; Forge protected via service accounts.

## Network paths
- Ingot → Anvil: assignments, labels, queue metadata.
- Anvil → Forge: sample fetch (or embedded in AssignmentIR).
- Anvil → storage: exports, artifacts, lineage records.

## Observability
- Emit LineageIR refs on assignment/label/eval run creation.
- Metrics: queue depth, assignment latency, label throughput, error rates; per tenant/queue.
- Logs: include `tenant_id`, `queue_id`, `assignment_id` in structured logs.

## Backups & retention
- Postgres backups nightly; labels and eval runs are system of record.
- Artifacts stored in S3/MinIO with lifecycle rules (configurable per tenant).
- Exports: provide signed URLs with TTL.

## Security
- Enforce `tenant_id` on all writes; reject cross-tenant reads.
- Queue-level RBAC: labelers vs auditors vs admins.
- Optional `PolicyIR` (future) to gate outputs and tool calls.

## Versioning & rollout
- Tag releases per service (`forge@vX`, `anvil@vY`, `ingot@vZ`).
- Use `/v1` API prefix; add `/v2` for breaking changes.
- Blue/green deploy Anvil and Ingot to avoid assignment loss; keep assignments idempotent.

## Local dev quickstart
- Run `mix phx.server` in each app (or umbrella); set `TENANT_ID=dev`, `QUEUE_ID=dev_queue`.
- Seed Anvil with a queue, schema, and sample; verify Ingot renders default component.
