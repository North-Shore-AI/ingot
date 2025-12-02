# Migration Guide: CNS-Hardcoded UI → Component-Driven Labeling

## Objective
Remove CNS hard-coding from Ingot and align with the shared IRs (AssignmentIR, SchemaIR, LabelIR). CNS becomes an external component package.

## Steps (Ingot)
1) **Routing**: Change labeling route to include `queue_id` (`/queues/:queue_id/label`). Pass `tenant_id` and `user_id` in session.
2) **Assignment fetch**: Replace calls to Forge with `Anvil.get_next_assignment(queue_id, user_id)` returning `AssignmentIR`.
3) **Component loading**: Use ComponentRegistry to load `component_module` from assignment metadata; fall back to DefaultComponent.
4) **Rendering**: Swap CNS LiveComponents for:
   ```elixir
   @component.render_sample(@assignment.sample, mode: :labeling, preprocessed: @preprocessed)
   @component.render_label_form(@assignment.schema, @label_data, show_help: @show_help)
   ```
5) **Assets**: Inject css/js from `required_assets/0` into layout head; register hooks listed.
6) **Submission**: POST `LabelIR` to Anvil with `assignment_id`, `queue_id`, `tenant_id`, `user_id`, `values`, `notes`, `time_spent_ms`, optional `lineage_ref`.
7) **State**: Maintain `@label_data` map instead of fixed rating fields; use schema defaults when present.
8) **Tests**: Update LiveView tests to use DOM IDs (`#label-form`, `#submit-button`) and mock AssignmentIR responses.

## Steps (Anvil)
1) Introduce `SchemaIR` and `AssignmentIR` structs/APIs; ensure queues carry `component_module` metadata.
2) Add `tenant_id` enforcement on queues/assignments/labels.
3) Provide REST endpoints for assignment fetch and label submit matching the IR.
4) Add optional `eval_runs` endpoint for human/model evals in same shape as LabelIR.

## Steps (Forge)
1) Emit `SampleIR` with tenant_id and artifacts; optional `DatasetIR` slices.
2) Provide REST to fetch samples/datasets by id and slice.

## Cleaning CNS references
- Remove CNS-specific LiveComponents from Ingot core; keep them in external package (e.g., `cns_ui_components`).
- Delete any CNS strings from templates/tests; replace with schema-driven assertions.

## Data compatibility
- For legacy labels, add a one-time migration to map old fields into `values` keyed by schema field name.
- Maintain exports via jsonl with `LabelIR` shape.

## Rollout checklist
- [ ] ComponentRegistry wired in LiveView
- [ ] Queue-aware routes
- [ ] Assignment fetch from Anvil
- [ ] DefaultComponent verified with SchemaIR examples
- [ ] CNS package registered externally via queue metadata
- [ ] API docs published (`api_guide.md`)
