defmodule Ingot.Components.SampleRendererTest do
  use ExUnit.Case, async: true

  alias Ingot.DTO.Sample

  # Test module that implements the SampleRenderer behavior
  defmodule TestRenderer do
    @behaviour Ingot.SampleRenderer

    @impl true
    def render_sample(sample, opts \\ []) do
      mode = Keyword.get(opts, :mode, :labeling)
      "<div>Sample #{sample.id} in #{mode} mode</div>"
    end

    @impl true
    def required_assets do
      %{
        css: ["/assets/test.css"],
        js: ["/assets/test.js"],
        hooks: [:TestHook]
      }
    end

    @impl true
    def preprocess_sample(sample) do
      %{
        preprocessed: true,
        payload_size: map_size(sample.payload)
      }
    end
  end

  # Test module without optional callback
  defmodule MinimalRenderer do
    @behaviour Ingot.SampleRenderer

    @impl true
    def render_sample(sample, _opts) do
      "<div>#{sample.id}</div>"
    end

    @impl true
    def required_assets do
      %{css: [], js: [], hooks: []}
    end
  end

  describe "SampleRenderer behavior" do
    setup do
      sample = %Sample{
        id: "sample-123",
        pipeline_id: "test-pipeline",
        payload: %{text: "test content", value: 42},
        artifacts: [],
        metadata: %{},
        created_at: DateTime.utc_now()
      }

      {:ok, sample: sample}
    end

    test "TestRenderer implements render_sample/2", %{sample: sample} do
      result = TestRenderer.render_sample(sample)
      assert result == "<div>Sample sample-123 in labeling mode</div>"
    end

    test "TestRenderer accepts mode option", %{sample: sample} do
      result = TestRenderer.render_sample(sample, mode: :review)
      assert result == "<div>Sample sample-123 in review mode</div>"
    end

    test "TestRenderer implements required_assets/0" do
      assets = TestRenderer.required_assets()
      assert assets.css == ["/assets/test.css"]
      assert assets.js == ["/assets/test.js"]
      assert assets.hooks == [:TestHook]
    end

    test "TestRenderer implements preprocess_sample/1", %{sample: sample} do
      result = TestRenderer.preprocess_sample(sample)
      assert result.preprocessed == true
      assert result.payload_size == 2
    end

    test "MinimalRenderer implements required callbacks without optional", %{sample: sample} do
      result = MinimalRenderer.render_sample(sample, [])
      assert result == "<div>sample-123</div>"

      assets = MinimalRenderer.required_assets()
      assert assets.css == []
      assert assets.js == []
      assert assets.hooks == []

      # Optional callback should not be exported
      refute function_exported?(MinimalRenderer, :preprocess_sample, 1)
    end
  end
end
