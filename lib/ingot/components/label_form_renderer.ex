defmodule Ingot.LabelFormRenderer do
  @moduledoc """
  Behavior for custom label form rendering.

  Implement this to provide domain-specific input widgets and validation
  for labeling tasks. This allows pluggable components to customize how
  label forms are rendered and validated without modifying Ingot's core code.

  ## Required Callbacks

  - `render_label_form/3` - Render label form as Phoenix.LiveView.Rendered or HTML-safe iodata

  ## Optional Callbacks

  - `validate_label/2` - Validate label data before submission

  ## Example

      defmodule MyApp.CustomLabelFormRenderer do
        @behaviour Ingot.LabelFormRenderer

        use Phoenix.Component

        @impl true
        def render_label_form(schema, label_data, opts \\\\ []) do
          assigns = %{schema: schema, label_data: label_data}

          ~H\"\"\"
          <div class="custom-label-form">
            <%= for field <- @schema.fields do %>
              <div class="field">
                <label><%= field.name %></label>
                <input type="range"
                       name={"label_data[\#{field.name}]"}
                       min={field.min}
                       max={field.max}
                       value={@label_data[field.name] || field.default} />
              </div>
            <% end %>
          </div>
          \"\"\"
        end

        @impl true
        def validate_label(label_data, schema) do
          required_fields = Enum.filter(schema.fields, & &1.required)

          missing = Enum.filter(required_fields, fn field ->
            not Map.has_key?(label_data, field.name)
          end)

          case missing do
            [] -> {:ok, label_data}
            fields ->
              errors = Enum.map(fields, &{&1.name, "is required"}) |> Map.new()
              {:error, errors}
          end
        end
      end
  """

  @doc """
  Render label form as Phoenix.LiveView.Rendered or HTML-safe iodata.

  ## Parameters

  - `schema` - Label schema from queue configuration, defines fields and their types
  - `label_data` - Current form state (map of field names to values)
  - `opts` - Keyword list of rendering options

  ## Schema Structure

  The schema typically contains:

  - `:fields` - List of field definitions, each with:
    - `:name` - Field name (string)
    - `:type` - Field type (e.g., "scale", "text", "boolean")
    - `:min`, `:max` - For scale/range inputs
    - `:default` - Default value
    - `:required` - Whether field is required

  ## Options

  - `:show_help` - Whether to show help text
  - `:disabled` - Whether form should be disabled
  - `:errors` - Validation errors to display

  ## Returns

  Phoenix.LiveView.Rendered struct or HTML-safe iodata that can be
  rendered in a LiveView template.

  ## Examples

      render_label_form(schema, %{}, [])
      render_label_form(schema, %{"coherence" => 4}, show_help: true)
  """
  @callback render_label_form(
              schema :: map(),
              label_data :: map(),
              opts :: Keyword.t()
            ) :: Phoenix.LiveView.Rendered.t() | iodata()

  @doc """
  Optional: validate label data before submission.

  This callback allows components to implement domain-specific validation
  rules beyond basic schema validation. For example, checking that certain
  combinations of values are valid, or that values meet specific constraints.

  ## Parameters

  - `label_data` - The label data to validate (map of field names to values)
  - `schema` - The label schema defining field constraints

  ## Returns

  - `{:ok, label_data}` - If validation passes, may return normalized/cleaned data
  - `{:error, errors}` - If validation fails, return map of field -> error message

  ## Examples

      def validate_label(label_data, schema) do
        coherence = label_data["coherence"] || 0
        groundedness = label_data["groundedness"] || 0

        if coherence >= 4 and groundedness < 2 do
          {:error, %{groundedness: "High coherence usually requires better grounding"}}
        else
          {:ok, label_data}
        end
      end
  """
  @callback validate_label(label_data :: map(), schema :: map()) ::
              {:ok, map()} | {:error, map()}

  @optional_callbacks [validate_label: 2]
end
