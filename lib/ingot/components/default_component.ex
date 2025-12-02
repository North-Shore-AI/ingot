defmodule Ingot.Components.DefaultComponent do
  @moduledoc """
  Default fallback component for sample and label rendering.

  This component provides generic rendering functionality that works
  with any sample type and label schema. It's used when:

  1. No custom component is configured for a queue
  2. A custom component fails to load
  3. Testing and development

  ## Sample Rendering

  - Displays sample ID
  - Renders artifacts (images displayed inline, other files as links)
  - Pretty-prints JSON payload

  ## Label Form Rendering

  - Generates form inputs based on schema field types
  - Supports: scale (range), text (textarea), boolean (checkbox), generic (text input)
  - No custom validation (uses standard schema validation)
  """

  use Phoenix.Component

  @behaviour Ingot.SampleRenderer
  @behaviour Ingot.LabelFormRenderer

  alias Ingot.DTO.Sample

  ## SampleRenderer Implementation

  @impl Ingot.SampleRenderer
  def render_sample(%Sample{} = sample, _opts) do
    assigns = %{sample: sample}

    ~H"""
    <div class="default-sample-display">
      <h3>Sample {@sample.id}</h3>

      <%= if @sample.artifacts != [] do %>
        <div class="artifacts">
          <%= for artifact <- @sample.artifacts do %>
            {render_artifact(artifact)}
          <% end %>
        </div>
      <% end %>

      <pre class="sample-payload"><%= format_payload(@sample.payload) %></pre>
    </div>
    """
  end

  @impl Ingot.SampleRenderer
  def required_assets do
    %{css: [], js: [], hooks: []}
  end

  # Note: We intentionally do NOT implement preprocess_sample/1 (optional callback)

  ## LabelFormRenderer Implementation

  @impl Ingot.LabelFormRenderer
  def render_label_form(schema, label_data, _opts) do
    assigns = %{schema: schema, label_data: label_data}

    ~H"""
    <div class="default-label-form">
      <%= for field <- @schema.fields do %>
        <div class="dimension">
          <label>{field.name}</label>
          {render_field(field, @label_data)}
        </div>
      <% end %>
    </div>
    """
  end

  # Note: We intentionally do NOT implement validate_label/2 (optional callback)

  ## Private Helper Functions

  defp render_artifact(artifact) do
    assigns = %{artifact: artifact}

    case artifact.artifact_type do
      :image ->
        ~H"""
        <img src={@artifact.url} alt={@artifact.filename} />
        """

      :json ->
        ~H"""
        <a href={@artifact.url}>{@artifact.filename}</a>
        """

      _ ->
        ~H"""
        <a href={@artifact.url}>{@artifact.filename}</a>
        """
    end
  end

  defp render_field(field, label_data) do
    case field.type do
      "scale" ->
        assigns = %{
          field: field,
          value: get_field_value(label_data, field.name, field[:default])
        }

        ~H"""
        <input
          type="range"
          name={"label_data[#{@field.name}]"}
          min={@field.min}
          max={@field.max}
          value={@value}
        />
        """

      "text" ->
        assigns = %{
          field: field,
          value: get_field_value(label_data, field.name, "")
        }

        ~H"""
        <textarea name={"label_data[#{@field.name}]"}><%= @value %></textarea>
        """

      "boolean" ->
        assigns = %{
          field: field,
          checked: get_field_value(label_data, field.name, false)
        }

        ~H"""
        <input type="checkbox" name={"label_data[#{@field.name}]"} checked={@checked} />
        """

      _ ->
        assigns = %{
          field: field,
          value: get_field_value(label_data, field.name, "")
        }

        ~H"""
        <input type="text" name={"label_data[#{@field.name}]"} value={@value} />
        """
    end
  end

  defp get_field_value(label_data, field_name, default) do
    # Try string key first, then atom key
    cond do
      Map.has_key?(label_data, field_name) ->
        Map.get(label_data, field_name)

      Map.has_key?(label_data, String.to_atom(field_name)) ->
        Map.get(label_data, String.to_atom(field_name))

      true ->
        default
    end
  end

  defp format_payload(payload) when is_map(payload) do
    case Jason.encode(payload, pretty: true) do
      {:ok, json} -> json
      {:error, _} -> inspect(payload, pretty: true)
    end
  end

  defp format_payload(payload) do
    inspect(payload, pretty: true)
  end
end
