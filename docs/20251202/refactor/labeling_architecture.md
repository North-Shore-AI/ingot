# North Shore Labeling Architecture (Forge / Anvil / Ingot)

## Purpose
A shared mental model for human-in-the-loop labeling and evaluation across the North Shore stack. CNS is a *consumer* of this system, never a dependency.

## Roles
- **Forge**: Generates samples and datasets. Emits `SampleIR` and `DatasetIR` slices. No UI logic.
- **Anvil**: Manages queues, assignments, schemas, labels, and eval runs. Exposes a stable API. Enforces tenancy and component selection.
- **Ingot**: UI shell. Resolves component modules per queue and renders forms/samples. Ships with a generic default component; custom components live in external packages.
- **Custom components**: Provide domain-specific rendering/validation (e.g., `CNS.IngotComponents`), loaded via `component_module` metadata on a queue.

## Flow (happy path)
1) **Forge** produces `SampleIR` objects and (optionally) `DatasetIR` slices.
2) **Anvil** registers queues with metadata, including `component_module` and `SchemaIR`.
3) **Ingot** mounts with `queue_id` and `tenant_id`, calls Anvil for `AssignmentIR`, and loads the component via ComponentRegistry.
4) User submits labels → **Anvil** stores `LabelIR` and links lineage refs. Eval runs use the same IR shape (human + model-generated).

## Tenancy and namespaces
- Every IR has `tenant_id` and (optionally) `namespace`.
- Ingot passes these through session to Anvil; Anvil enforces access per queue.
- Forge may emit datasets per tenant/namespace; Anvil queues reference them by ID.

## Lineage & observability
- Each Assignment/Label/EvalRun carries a `lineage_ref` (LineageIR) for provenance.
- Artifacts (exports, rendered views) should be recorded in LineageIR and can be stored via S3/MinIO.

## What is *not* allowed
- CNS strings or code in Ingot/Anvil/Forge core.
- Hard-coded dimensions or sample payload shapes in Ingot. Everything comes from `SchemaIR` and `SampleIR`.
- UI components defined inside Ingot core beyond the default generic renderer.

## Object glossary (see IR Spec for details)
- `SampleIR`: Sample payload + artifacts (Forge emits).
- `DatasetIR`: Versioned datasets/slices (Forge/Anvil share).
- `AssignmentIR`: A unit of work tying queue → sample → schema (Anvil emits).
- `SchemaIR`: Declarative form/schema definition (Anvil owns).
- `LabelIR`: Human label output (Anvil stores).
- `EvalRunIR`: Human or model eval run (Anvil stores; Crucible consumes).

## Deployment shape
- Small: All three apps in one cluster (dev).
- Prod: Forge (sample pipelines) + Anvil (API, queues, labels) + Ingot (UI) deployed separately; shared DB/S3 and auth.

## Success criteria
- Add a queue with only metadata (schema + component) and get a working UI without code changes.
- CNS (or any domain) plugs in by shipping its own component package and queue config—no PRs to Ingot.
