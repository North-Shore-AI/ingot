# Ingot Integration Guide (Component-Driven UI)

## Goal
Render any queue by metadata only: Ingot asks Anvil for an Assignment, loads the component module from queue metadata, and renders schema-driven UI. CNS and other domains live in their own component packages.

## Runtime Flow
1) Route: `/queues/:queue_id/label` (LiveView). Session carries `tenant_id`, `user_id`.
2) Ingot calls `Anvil.get_next_assignment(queue_id, user_id)` → `AssignmentIR`.
3) ComponentRegistry resolves `component_module` from `assignment.metadata["component_module"]` (else default).
4) If `preprocess_sample/1` exists, run once and pass via `preprocessed` option.
5) Render sample and form:
```elixir
@component.render_sample(@assignment.sample, mode: :labeling, preprocessed: @preprocessed)
@component.render_label_form(@assignment.schema, @label_data, show_help: @show_help)
```
6) Include assets from `component.required_assets/0` (css/js/hooks) in the layout head.
7) On submit, post `LabelIR` to Anvil; include `tenant_id`, `queue_id`, `assignment_id`, `lineage_ref` if present.

## Example Queue Metadata (Anvil)
```json
{
  "queue_id": "q_news_v1",
  "tenant_id": "tenant_acme",
  "schema_id": "schema_news_eval",
  "component_module": "Acme.NewsComponents", 
  "metadata": {
    "priority": "normal"
  }
}
```

## Example Component (external package)
```elixir
defmodule Acme.NewsComponents do
  use Phoenix.Component
  @behaviour Ingot.SampleRenderer
  @behaviour Ingot.LabelFormRenderer

  @impl true
  def render_sample(sample, opts \\ []) do
    assigns = %{sample: sample, pre: opts[:preprocessed]}
    ~H"""
    <div class="prose">
      <h2>{@sample.payload["headline"]}</h2>
      <p>{@sample.payload["body"]}</p>
    </div>
    """
  end

  @impl true
  def required_assets, do: %{css: ["/assets/acme/news.css"], js: [], hooks: []}

  @impl true
  def render_label_form(schema, label_data, _opts) do
    assigns = %{schema: schema, data: label_data}
    ~H"""
    <div>
      <%= for field <- @schema.fields do %>
        <label class="block font-semibold">{field.name}</label>
        <input type="range" name={"label_data[#{field.name}]"}
               min={field.min || 1} max={field.max || 5}
               value={Map.get(@data, field.name, field.default || 3)} />
      <% end %>
    </div>
    """
  end
end
```

## Default Component
- Keep `Ingot.Components.DefaultComponent` to render any `SchemaIR` with scale/text/boolean/select.
- Use when `component_module` missing or fails to load.

## Assets Injection
- In layout (before `</head>`), include css/js from `@component.required_assets/0`.
- Register hooks in `app.js` when listed.

## Validation
- Optional `validate_label/2` on component; Ingot should call it before submit when exported.
- Anvil performs server-side validation against `SchemaIR` regardless of client.

## Testing hooks
- Add DOM IDs on key elements (`#label-form`, `#submit-button`) in templates for LiveView tests.
- Use LiveViewTest selectors against IDs, not text content.

## Error Handling
- If component fails to load: log warning, fall back to default component, surface flash error.
- If assignment fetch fails: redirect to home or show queue empty state.

## Accessibility & UX
- Respect `<Layouts.app flash={@flash} ...>` in LiveViews.
- Use `<.input>` components where applicable (for generic/default forms).
- Provide keyboard shortcuts only in Ingot core; domain components should remain lightweight.
