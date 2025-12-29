# Implementation Phases (Forge / Anvil / Ingot)

## Phase 1: Ingot refactor (UI decouple)
- Add queue-aware routes (`/queues/:queue_id/label`) and pass `tenant_id`.
- Fetch `AssignmentIR` from Anvil; remove Forge direct calls in LiveView.
- Load component via ComponentRegistry from `component_module`; fall back to DefaultComponent.
- Render sample/form through behaviors; inject component assets; keep `<Layouts.app ...>`.
- Submit labels as `LabelIR` to Anvil; maintain `@label_data` map.
- Update tests to use DOM IDs and AssignmentIR fixtures.

## Phase 2: Anvil/Forge IR alignment
- Define and expose `SchemaIR`, `AssignmentIR`, `LabelIR`, `EvalRunIR`, `SampleIR`, `DatasetIR` modules + REST `/v1` using the shared `labeling_ir` library.
- Enforce `component_module` in queue metadata; add tenancy checks on all endpoints.
- Provide dataset/slice fetch in Forge; queue uses sample refs; Anvil may embed samples in assignments.
- Export labels/evals as `BatchIR` jsonl/msgpack.

## Phase 3: Docs, defaults, API façade
- Publish the seven docs (this directory) and keep them synced with code.
- Add starter schemas/layouts and a demo queue using DefaultComponent.
- Provide a minimal REST façade for external (Python/JS) clients (assignments, labels, datasets, eval runs).

## Phase 4: Optional extensions
- MemoryIR mount for retrieval-backed UI and context sharing.
- PolicyIR for output gating/safety and queue-level policies.
- PackageIR (Agent/App manifest) if you want deployable bundles.

## Success checkpoints
- P1: Ingot renders any SchemaIR via default component; CNS removed from core.
- P2: Anvil/Forge APIs return IR-shaped JSON; queues configurable by metadata only.
- P3: External clients can label via REST; docs describe end-to-end flow.
- P4: Retrieval/safety integrated without breaking core contracts.
