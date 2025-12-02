defmodule Ingot.Components.LabelFormRendererTest do
  use ExUnit.Case, async: true

  # Test module that implements the LabelFormRenderer behavior
  defmodule TestFormRenderer do
    @behaviour Ingot.LabelFormRenderer

    @impl true
    def render_label_form(schema, label_data, opts \\ []) do
      field_count = length(schema.fields)
      data_count = map_size(label_data)
      show_help = Keyword.get(opts, :show_help, false)

      help_text = if show_help, do: " with help", else: ""
      "<form>Fields: #{field_count}, Data: #{data_count}#{help_text}</form>"
    end

    @impl true
    def validate_label(label_data, schema) do
      required_fields = Enum.filter(schema.fields, & &1[:required])

      missing =
        Enum.filter(required_fields, fn field ->
          not Map.has_key?(label_data, field.name) and
            not Map.has_key?(label_data, String.to_atom(field.name))
        end)

      case missing do
        [] ->
          {:ok, label_data}

        fields ->
          errors =
            Enum.map(fields, fn field ->
              {field.name, "is required"}
            end)
            |> Map.new()

          {:error, errors}
      end
    end
  end

  # Test module without optional callback
  defmodule MinimalFormRenderer do
    @behaviour Ingot.LabelFormRenderer

    @impl true
    def render_label_form(_schema, _label_data, _opts) do
      "<form>Minimal form</form>"
    end
  end

  describe "LabelFormRenderer behavior" do
    setup do
      schema = %{
        fields: [
          %{name: "coherence", type: "rating", min: 1, max: 5, required: true},
          %{name: "notes", type: "text", required: false}
        ]
      }

      {:ok, schema: schema}
    end

    test "TestFormRenderer implements render_label_form/3", %{schema: schema} do
      label_data = %{"coherence" => 4}
      result = TestFormRenderer.render_label_form(schema, label_data)
      assert result == "<form>Fields: 2, Data: 1</form>"
    end

    test "TestFormRenderer accepts options", %{schema: schema} do
      label_data = %{}
      result = TestFormRenderer.render_label_form(schema, label_data, show_help: true)
      assert result == "<form>Fields: 2, Data: 0 with help</form>"
    end

    test "TestFormRenderer implements validate_label/2", %{schema: schema} do
      # Valid data
      label_data = %{"coherence" => 4, "notes" => "test"}
      assert {:ok, ^label_data} = TestFormRenderer.validate_label(label_data, schema)
    end

    test "TestFormRenderer validates required fields", %{schema: schema} do
      # Missing required field
      label_data = %{"notes" => "test"}
      assert {:error, errors} = TestFormRenderer.validate_label(label_data, schema)
      assert errors["coherence"] == "is required"
    end

    test "TestFormRenderer accepts atom keys for validation", %{schema: schema} do
      # Valid data with atom keys
      label_data = %{coherence: 4}
      assert {:ok, ^label_data} = TestFormRenderer.validate_label(label_data, schema)
    end

    test "MinimalFormRenderer implements required callbacks without optional", %{
      schema: schema
    } do
      result = MinimalFormRenderer.render_label_form(schema, %{}, [])
      assert result == "<form>Minimal form</form>"

      # Optional callback should not be exported
      refute function_exported?(MinimalFormRenderer, :validate_label, 2)
    end
  end
end
