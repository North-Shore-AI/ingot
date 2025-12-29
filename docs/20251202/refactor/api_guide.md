# Labeling API Guide (Forge / Anvil)

Audience: non-Elixir clients (Python/JS) and Ingot UI. Transport: REST/JSON (recommended) with tenant scoping. Structs are defined in the shared `labeling_ir` library.

## Auth & tenancy
- Header `X-Tenant-ID: <tenant>` required on all writes.
- Auth token (e.g., `Authorization: Bearer ...`) to be enforced per deployment.

## Assignments
- `GET /v1/queues/:queue_id/assignments/next?user_id=...`
  - Returns `AssignmentIR` (schema + sample + component_module metadata).
- `POST /v1/assignments/:id/ack` (optional) to mark started.

## Labels
- `POST /v1/labels`
```json
{
  "assignment_id": "asst_123",
  "queue_id": "q1",
  "tenant_id": "tenant_acme",
  "user_id": "user_42",
  "values": {"coherence": 4, "grounded": 5},
  "notes": "solid",
  "time_spent_ms": 12000,
  "lineage_ref": null,
  "metadata": {}
}
```
- Response: stored `LabelIR` (with `id`, `created_at`).

## Schemas
- `GET /v1/schemas/:id` → `SchemaIR`
- `POST /v1/schemas` → create (admin path), returns `id`.

## Queues
- `GET /v1/queues/:id` → metadata (includes `component_module`, `schema_id`).
- `POST /v1/queues` (admin) → create/update queue with metadata and schema reference.

## Samples & Datasets (Forge)
- `GET /v1/samples/:id` → `SampleIR`
- `POST /v1/samples` → create sample (admin/pipeline)
- `GET /v1/datasets/:id` → `DatasetIR`
- `GET /v1/datasets/:id/slices/:name` → slice definition

## Eval Runs
- `POST /v1/eval_runs`
```json
{
  "dataset_id": "ds1",
  "slice": "validation",
  "tenant_id": "tenant_acme",
  "run_type": "human",
  "model_ref": null,
  "metrics": {"accuracy": 0.82},
  "artifacts": [],
  "metadata": {"prompt": "v3"}
}
```
- `GET /v1/eval_runs/:id`

## Exports
- `GET /v1/queues/:id/labels/export?format=jsonl` → signed URL or stream.
- `GET /v1/eval_runs/:id/artifacts` → list of artifact refs.

## Errors
- 401 unauthorized, 403 forbidden (tenant/queue access), 404 not found, 422 validation (schema mismatch).

## Versioning
- Prefix with `/v1`. Introduce `/v2` for breaking changes (see `ir_governance.md`).
