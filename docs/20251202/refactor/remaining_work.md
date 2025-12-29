# Remaining Work After ADR-001/002 Implementation

Status: draft  
Scope: Forge / Anvil / Ingot / labeling_ir  
Date: 2025-12-02

## Context
ADR-001 and ADR-002 are implemented with shared IR structs, `/v1` stubs, and Ingot’s componentized LiveView. The current code is test-green but runs in-memory for the service APIs and uses mock adapters in Ingot. This document lists what is left to harden for production parity.

## labeling_ir (Shared Library)
- **Versioned fixtures**: Add JSON fixtures per IR version (e.g., `test/fixtures/ir/v1/*.json`) to lock compatibility for future evolutions.
- **Governance hooks**: Document and enforce the process for adding optional fields (changelog entries, fixtures, and adapters) to stay compliant with ADR-002.

## Anvil
- **Mount `/v1` router**: Plug `Anvil.API.Router` into the main endpoint or a dedicated Plug pipeline; ensure `x-tenant-id` is enforced consistently.
- **Persisted storage**: Replace ETS state with Repo-backed tables (schemas, queues, samples, assignments, labels, datasets) and transactional creation.
- **Auth/RBAC**: Wire existing auth modules to protect `/v1` endpoints; ensure queue access and tenant isolation are enforced.
- **Lineage and exports**: Persist `lineage_ref` and expose exports for labels/eval runs once the database layer is active.
- **Queue/component metadata**: Store and validate `component_module` on queues; surface warnings when modules are missing while still tolerating unknown fields.

## Forge
- **Mount `/v1` router**: Attach `Forge.API.Router` to the endpoint; enforce `x-tenant-id`.
- **Persisted storage**: Back samples/datasets/slices with Repo or configured storage instead of ETS.
- **Pipeline integration**: Feed SampleIR/DatasetIR from pipeline outputs; keep artifacts and lineage refs intact.
- **Auth**: Apply auth/RBAC for pipeline writes and sample reads.
- **Exports/fixtures**: Add fixtures for dataset slices and golden SampleIR payloads to guard compatibility.

## Ingot
- **HTTP adapters**: Add real HTTP adapters for Anvil/Forge `/v1` and switch config from mocks in non-test environments; include tenancy headers and error normalization.
- **Dashboard parity**: Restore queue statistics and progress once upstream stats land in `/v1`; remove legacy DTO assumptions.
- **Component assets**: Extend `assets/js/app.js` to register hooks listed by `required_assets/0` when using custom components; document expected hook names.
- **Telemetry/auth hooks**: Reintroduce queue-access checks in LiveView `on_mount` once Anvil exposes queue auth over `/v1`; emit telemetry spans around assignment fetch and label submit.
- **Docs/examples**: Publish a minimal example component package (outside core) and update the integration guide with HTTP adapter usage and asset injection expectations.
