# IR Governance (Labeling Stack)

## Scope
- `SampleIR`, `DatasetIR`, `SchemaIR`, `AssignmentIR`, `LabelIR`, `EvalRunIR`, `Artifact` (and future `MemoryIR`, `PolicyIR`).

## Versioning
- Use `/v1` REST namespace and module names without suffix for current IR.
- Breaking changes → new version (`/v2`, `SampleIR.V2`). Maintain old version until deprecation window ends.
- Additive/optional fields are allowed without bump.

## Change process
1) Draft change (doc PR) describing schema deltas and migration steps.
2) Add tests/fixtures for both old and new versions if breaking.
3) Implement adapters/migration paths (e.g., read v1, emit v2).
4) Announce deprecation window and timelines.

## Extension points
- Prefer `metadata :: map()` for service-specific additions.
- Do not overload core fields; if you need new behavior, add a new optional field with clear semantics.
- Keep enums closed; extend via new enum values plus compatibility handling.

## Compatibility contract
- Readers must tolerate unknown fields.
- Writers must include required fields of the target version.
- Ingot must gracefully fall back to DefaultComponent when component module missing/invalid.

## Deprecation
- Mark fields as deprecated in docs; remove only in next major version.
- Provide export scripts to translate old labels to new shape when removing fields.

## Testing & fixtures
- Maintain JSON fixtures for each IR version under `test/fixtures/ir/` (per service).
- Add golden-path and error-path tests for API endpoints when IR changes.

## Release notes
- Each release of Forge/Anvil/Ingot must include IR changes in changelog, with migration notes and timelines.
