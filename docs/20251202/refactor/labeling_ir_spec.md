# Labeling IR Specification

Version: 2025-12-02 (initial)  
Scope: Forge, Anvil, Ingot, external clients  
Source: Shared library `labeling_ir` (GitHub: `North-Shore-AI/labeling_ir`)

## Common fields
- `tenant_id :: String` (required)
- `namespace :: String | nil`
- `lineage_ref :: LineageIR.TraceRef | nil`
- `metadata :: map()` for extensibility

## SampleIR (Forge)
```elixir
%SampleIR{
  id: String.t(),
  tenant_id: String.t(),
  pipeline_id: String.t(),
  payload: map(),          # domain payload
  artifacts: [Artifact.t()],# signed URLs or blobs
  metadata: map(),
  created_at: DateTime.t()
}
```

## DatasetIR
Represents a versioned dataset and slices.
```elixir
%DatasetIR{
  id: String.t(),
  tenant_id: String.t(),
  version: String.t(),
  slices: [%{name: String.t(), sample_ids: [String.t()], filter: map()}],
  source_refs: [LineageIR.ArtifactRef.t()],
  metadata: map(),
  created_at: DateTime.t()
}
```

## SchemaIR (Anvil)
Declarative label schema. UI components read this, no hard-coded fields.
```elixir
%SchemaIR{
  id: String.t(),
  tenant_id: String.t(),
  fields: [
    %{
      name: String.t(),
      type: :scale | :text | :boolean | :select | :multiselect,
      required: boolean(),
      min: integer() | nil,
      max: integer() | nil,
      default: term() | nil,
      options: [String.t()] | nil,
      help: String.t() | nil
    }
  ],
  layout: map() | nil,           # optional layout hints
  component_module: String.t() | nil, # override per schema if needed
  metadata: map()
}
```

## AssignmentIR (Anvil)
```elixir
%AssignmentIR{
  id: String.t(),
  queue_id: String.t(),
  tenant_id: String.t(),
  sample: SampleIR.t(),
  schema: SchemaIR.t(),
  existing_labels: [LabelIR.t()],
  expires_at: DateTime.t() | nil,
  metadata: map()
}
```

## LabelIR (Anvil)
```elixir
%LabelIR{
  id: String.t(),
  assignment_id: String.t(),
  sample_id: String.t(),
  queue_id: String.t(),
  tenant_id: String.t(),
  user_id: String.t(),
  values: map(),         # keyed by field name
  notes: String.t() | nil,
  time_spent_ms: integer(),
  created_at: DateTime.t(),
  lineage_ref: LineageIR.TraceRef | nil,
  metadata: map()
}
```

## EvalRunIR (Anvil / Crucible bridge)
Supports human or model eval runs in the same shape.
```elixir
%EvalRunIR{
  id: String.t(),
  tenant_id: String.t(),
  dataset_id: String.t(),
  slice: String.t() | nil,
  model_ref: String.t() | nil,   # nil for pure human eval
  run_type: :human | :model,
  metrics: map(),
  artifacts: [LineageIR.ArtifactRef.t()],
  lineage_ref: LineageIR.TraceRef | nil,
  metadata: map(),
  created_at: DateTime.t()
}
```

## Artifact (used by SampleIR)
```elixir
%Artifact{
  id: String.t(),
  url: String.t(),
  filename: String.t(),
  artifact_type: :image | :json | :text | :other,
  mime: String.t() | nil,
  expires_at: DateTime.t() | nil,
  metadata: map()
}
```

## API transport
- REST/JSON (preferred) and/or gRPC; fields and enums should match the IR.
- `tenant_id` required on write; authz enforced per queue.
- `lineage_ref` optional but recommended; when omitted, the service can create a new trace and return it.

## Versioning and compatibility
- Additive changes via new optional fields.
- Breaking changes bump version suffix (e.g., `v2` endpoints) and document migration in `ir_governance.md`.
