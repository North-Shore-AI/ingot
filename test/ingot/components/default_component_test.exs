defmodule Ingot.Components.DefaultComponentTest do
  use ExUnit.Case, async: true

  alias Ingot.Components.DefaultComponent
  alias Ingot.DTO.{Artifact, Sample}

  describe "render_sample/2" do
    setup do
      sample = %Sample{
        id: "sample-123",
        pipeline_id: "test-pipeline",
        payload: %{
          text: "test content",
          value: 42,
          nested: %{key: "value"}
        },
        artifacts: [],
        metadata: %{model: "test"},
        created_at: ~U[2025-01-01 12:00:00Z]
      }

      {:ok, sample: sample}
    end

    test "renders sample with basic payload", %{sample: sample} do
      result = DefaultComponent.render_sample(sample, [])

      # Should be rendered Phoenix component output (iodata or Rendered struct)
      result_string = result |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

      # Check for sample ID
      assert result_string =~ "sample-123"

      # Check for JSON payload rendering (HTML-escaped)
      assert result_string =~ ~s(&quot;text&quot;) or result_string =~ ~s("text")
      assert result_string =~ ~s(&quot;test content&quot;) or result_string =~ ~s("test content")
      assert result_string =~ ~s(&quot;value&quot;) or result_string =~ ~s("value")
      assert result_string =~ "42"
    end

    test "renders sample with image artifact" do
      artifact = %Artifact{
        id: "artifact-1",
        sample_id: "sample-123",
        artifact_type: :image,
        url: "https://example.com/image.jpg",
        filename: "image.jpg",
        size_bytes: 1024,
        content_type: "image/jpeg"
      }

      sample = %Sample{
        id: "sample-123",
        pipeline_id: "test-pipeline",
        payload: %{},
        artifacts: [artifact],
        metadata: %{},
        created_at: ~U[2025-01-01 12:00:00Z]
      }

      result = DefaultComponent.render_sample(sample, [])
      result_string = result |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

      # Check for image rendering
      assert result_string =~ ~s(<img)
      assert result_string =~ ~s(src="https://example.com/image.jpg")
      assert result_string =~ ~s(alt="image.jpg")
    end

    test "renders sample with JSON artifact" do
      artifact = %Artifact{
        id: "artifact-1",
        sample_id: "sample-123",
        artifact_type: :json,
        url: "https://example.com/data.json",
        filename: "data.json",
        size_bytes: 512,
        content_type: "application/json"
      }

      sample = %Sample{
        id: "sample-123",
        pipeline_id: "test-pipeline",
        payload: %{key: "value"},
        artifacts: [artifact],
        metadata: %{},
        created_at: ~U[2025-01-01 12:00:00Z]
      }

      result = DefaultComponent.render_sample(sample, [])
      result_string = result |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

      # Check for JSON artifact link
      assert result_string =~ ~s(data.json)
      assert result_string =~ ~s(https://example.com/data.json)
    end

    test "renders sample with generic artifact" do
      artifact = %Artifact{
        id: "artifact-1",
        sample_id: "sample-123",
        artifact_type: :file,
        url: "https://example.com/document.pdf",
        filename: "document.pdf",
        size_bytes: 2048,
        content_type: "application/pdf"
      }

      sample = %Sample{
        id: "sample-123",
        pipeline_id: "test-pipeline",
        payload: %{},
        artifacts: [artifact],
        metadata: %{},
        created_at: ~U[2025-01-01 12:00:00Z]
      }

      result = DefaultComponent.render_sample(sample, [])
      result_string = result |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

      # Check for generic artifact link
      assert result_string =~ ~s(<a)
      assert result_string =~ ~s(href="https://example.com/document.pdf")
      assert result_string =~ ~s(document.pdf)
    end

    test "renders sample with multiple artifacts" do
      artifacts = [
        %Artifact{
          id: "artifact-1",
          sample_id: "sample-123",
          artifact_type: :image,
          url: "https://example.com/img1.jpg",
          filename: "img1.jpg",
          size_bytes: 1024,
          content_type: "image/jpeg"
        },
        %Artifact{
          id: "artifact-2",
          sample_id: "sample-123",
          artifact_type: :file,
          url: "https://example.com/doc.pdf",
          filename: "doc.pdf",
          size_bytes: 2048,
          content_type: "application/pdf"
        }
      ]

      sample = %Sample{
        id: "sample-123",
        pipeline_id: "test-pipeline",
        payload: %{},
        artifacts: artifacts,
        metadata: %{},
        created_at: ~U[2025-01-01 12:00:00Z]
      }

      result = DefaultComponent.render_sample(sample, [])
      result_string = result |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

      # Both artifacts should be rendered
      assert result_string =~ "img1.jpg"
      assert result_string =~ "doc.pdf"
    end

    test "ignores opts parameter", %{sample: sample} do
      result1 = DefaultComponent.render_sample(sample, [])
      result2 = DefaultComponent.render_sample(sample, mode: :review, foo: :bar)

      # Results should be the same since opts are ignored
      assert result1 |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary() ==
               result2 |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
    end
  end

  describe "required_assets/0" do
    test "returns empty asset lists" do
      assets = DefaultComponent.required_assets()

      assert assets.css == []
      assert assets.js == []
      assert assets.hooks == []
    end
  end

  describe "render_label_form/3" do
    setup do
      schema = %{
        fields: [
          %{name: "coherence", type: "scale", min: 1, max: 5, default: 3},
          %{name: "notes", type: "text"},
          %{name: "verified", type: "boolean"},
          %{name: "category", type: "other"}
        ]
      }

      {:ok, schema: schema}
    end

    test "renders form with scale field", %{schema: schema} do
      label_data = %{"coherence" => 4}

      result = DefaultComponent.render_label_form(schema, label_data, [])
      result_string = result |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

      # Check for scale input
      assert result_string =~ ~s(<input)
      assert result_string =~ ~s(type="range")
      assert result_string =~ ~s(name="label_data[coherence]")
      assert result_string =~ ~s(min="1")
      assert result_string =~ ~s(max="5")
      assert result_string =~ ~s(value="4")
    end

    test "uses default value for scale field when no data provided", %{schema: schema} do
      label_data = %{}

      result = DefaultComponent.render_label_form(schema, label_data, [])
      result_string = result |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

      # Should use default value
      assert result_string =~ ~s(value="3")
    end

    test "renders form with text field", %{schema: schema} do
      label_data = %{"notes" => "test notes"}

      result = DefaultComponent.render_label_form(schema, label_data, [])
      result_string = result |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

      # Check for textarea
      assert result_string =~ ~s(<textarea)
      assert result_string =~ ~s(name="label_data[notes]")
      assert result_string =~ "test notes"
    end

    test "renders empty textarea when no data provided", %{schema: schema} do
      label_data = %{}

      result = DefaultComponent.render_label_form(schema, label_data, [])
      result_string = result |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

      # Check for empty textarea
      assert result_string =~ ~s(<textarea)
      assert result_string =~ ~s(name="label_data[notes]")
    end

    test "renders form with boolean field", %{schema: schema} do
      label_data = %{"verified" => true}

      result = DefaultComponent.render_label_form(schema, label_data, [])
      result_string = result |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

      # Check for checkbox
      assert result_string =~ ~s(<input)
      assert result_string =~ ~s(type="checkbox")
      assert result_string =~ ~s(name="label_data[verified]")
      assert result_string =~ ~s(checked)
    end

    test "renders unchecked checkbox when boolean is false", %{schema: schema} do
      label_data = %{"verified" => false}

      result = DefaultComponent.render_label_form(schema, label_data, [])
      result_string = result |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

      # Check for unchecked checkbox
      assert result_string =~ ~s(type="checkbox")
      refute result_string =~ ~s(checked)
    end

    test "renders form with generic field type", %{schema: schema} do
      label_data = %{"category" => "test-category"}

      result = DefaultComponent.render_label_form(schema, label_data, [])
      result_string = result |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

      # Check for text input (default for unknown types)
      assert result_string =~ ~s(<input)
      assert result_string =~ ~s(type="text")
      assert result_string =~ ~s(name="label_data[category]")
      assert result_string =~ ~s(value="test-category")
    end

    test "renders all fields in schema", %{schema: schema} do
      label_data = %{}

      result = DefaultComponent.render_label_form(schema, label_data, [])
      result_string = result |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

      # All field names should appear as labels
      assert result_string =~ "coherence"
      assert result_string =~ "notes"
      assert result_string =~ "verified"
      assert result_string =~ "category"
    end

    test "handles string keys in label_data", %{schema: schema} do
      label_data = %{"coherence" => 5, "notes" => "string keys"}

      result = DefaultComponent.render_label_form(schema, label_data, [])
      result_string = result |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

      assert result_string =~ ~s(value="5")
      assert result_string =~ "string keys"
    end

    test "handles atom keys in label_data", %{schema: schema} do
      label_data = %{coherence: 2, notes: "atom keys"}

      result = DefaultComponent.render_label_form(schema, label_data, [])
      result_string = result |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

      assert result_string =~ ~s(value="2")
      assert result_string =~ "atom keys"
    end

    test "ignores opts parameter", %{schema: schema} do
      label_data = %{}

      result1 = DefaultComponent.render_label_form(schema, label_data, [])
      result2 = DefaultComponent.render_label_form(schema, label_data, show_help: true)

      # Results should be the same since opts are ignored
      assert result1 |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary() ==
               result2 |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()
    end
  end

  describe "behavior implementation" do
    test "implements SampleRenderer behavior" do
      all_behaviors =
        DefaultComponent.module_info(:attributes)
        |> Enum.filter(fn {key, _value} -> key == :behaviour end)
        |> Enum.flat_map(fn {:behaviour, behaviors} -> behaviors end)

      assert Ingot.SampleRenderer in all_behaviors
    end

    test "implements LabelFormRenderer behavior" do
      all_behaviors =
        DefaultComponent.module_info(:attributes)
        |> Enum.filter(fn {key, _value} -> key == :behaviour end)
        |> Enum.flat_map(fn {:behaviour, behaviors} -> behaviors end)

      assert Ingot.LabelFormRenderer in all_behaviors
    end

    test "does not implement optional preprocess_sample/1" do
      refute function_exported?(DefaultComponent, :preprocess_sample, 1)
    end

    test "does not implement optional validate_label/2" do
      refute function_exported?(DefaultComponent, :validate_label, 2)
    end
  end
end
