# ADR-001: Adopt IR-Driven, Componentized Labeling for Forge/Anvil/Ingot

## Status
Accepted (2025-12-02)

## Context
Labeling UI logic is currently hard-coded (e.g., CNS-specific in Ingot) and IRs are implicit. We need a generic, tenant-aware labeling pipeline where domains (CNS or others) plug in via components, not code changes.

## Decision
- Standardize on the IR set defined in `../labeling_ir_spec.md` (SampleIR, DatasetIR, SchemaIR, AssignmentIR, LabelIR, EvalRunIR, Artifact) with tenancy and optional lineage.
- Enforce the roles described in `../labeling_architecture.md`: Forge emits samples/datasets, Anvil serves assignments/labels with schemas and queue metadata, Ingot is a thin shell that renders via ComponentRegistry.
- Refactor Ingot to fetch `AssignmentIR` from Anvil, resolve `component_module` per queue, render via behaviors (SampleRenderer/LabelFormRenderer), and submit `LabelIR` back to Anvil. DefaultComponent remains for generic schemas; all domain components live outside Ingot.
- Expose `/v1` REST endpoints in Anvil/Forge per `../api_guide.md` and align code with the staged plan in `../implementation_phases.md`.

## Consequences
- CNS and other domains ship separate component packages and queue metadata; no domain code in Ingot core.
- Tenancy and lineage become first-class on assignments/labels/eval runs.
- API consumers (Python/JS) get stable REST aligned to the IR spec; exports use BatchIR formats.
- Migration steps are defined in `../migration_guide.md`; ops/topology guidance in `../ops_topology.md`.

## References
- `../labeling_ir_spec.md`
- `../labeling_architecture.md`
- `../ingot_integration_guide.md`
- `../api_guide.md`
- `../migration_guide.md`
- `../ops_topology.md`
- `../implementation_phases.md`
- Shared IR library: `https://github.com/North-Shore-AI/labeling_ir`
