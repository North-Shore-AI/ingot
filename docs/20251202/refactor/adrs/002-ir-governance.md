# ADR-002: Govern Labeling IR Versions and Compatibility

## Status
Accepted (2025-12-02)

## Context
Multiple services (Forge, Anvil, Ingot, external clients) will consume and produce the labeling IRs. Without versioning and deprecation rules, future changes will break clients and UI components.

## Decision
- Adopt the governance rules in `../ir_governance.md` for all labeling IRs (`SampleIR`, `DatasetIR`, `SchemaIR`, `AssignmentIR`, `LabelIR`, `EvalRunIR`, `Artifact`).
- Use `/v1` REST namespace and additive changes by default; breaking changes require a new version (e.g., `/v2`) and documented migration.
- Maintain JSON fixtures and tests per IR version; tolerate unknown fields on read; components must gracefully fall back to DefaultComponent if custom modules fail.
- Record IR changes in release notes and follow the change process (draft → tests/fixtures → adapters → announce deprecation window).

## Consequences
- Clients can rely on stable contracts and clear upgrade paths.
- Services must keep backward compatibility until deprecation windows expire.
- Contributors follow a standard process for schema evolution, reducing drift across Forge/Anvil/Ingot.

## References
- `../ir_governance.md`
- `../labeling_ir_spec.md`
- `../implementation_phases.md`
- Shared IR library: `https://github.com/North-Shore-AI/labeling_ir`
