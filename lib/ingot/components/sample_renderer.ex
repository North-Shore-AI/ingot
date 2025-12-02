defmodule Ingot.SampleRenderer do
  @moduledoc """
  Behavior for custom sample rendering.

  Implement this to provide domain-specific sample visualization.
  This allows pluggable components to customize how samples are displayed
  in the labeling interface without modifying Ingot's core code.

  ## Required Callbacks

  - `render_sample/2` - Render sample content as Phoenix.LiveView.Rendered or HTML-safe iodata
  - `required_assets/0` - Return list of CSS/JS assets required by this component

  ## Optional Callbacks

  - `preprocess_sample/1` - Preprocess sample data before rendering (for expensive computations)

  ## Example

      defmodule MyApp.CustomSampleRenderer do
        @behaviour Ingot.SampleRenderer

        use Phoenix.Component

        @impl true
        def render_sample(sample, opts \\\\ []) do
          mode = Keyword.get(opts, :mode, :labeling)

          assigns = %{sample: sample, mode: mode}

          ~H\"\"\"
          <div class="custom-sample">
            <h3>Sample <%= @sample.id %></h3>
            <pre><%= inspect(@sample.payload, pretty: true) %></pre>
          </div>
          \"\"\"
        end

        @impl true
        def required_assets do
          %{
            css: ["/assets/my_app/custom.css"],
            js: ["/assets/my_app/custom.js"],
            hooks: [:CustomHook]
          }
        end

        @impl true
        def preprocess_sample(sample) do
          # Expensive computation done once on mount
          %{
            processed_data: parse_complex_payload(sample.payload),
            summary: generate_summary(sample.payload)
          }
        end
      end
  """

  alias Ingot.DTO.Sample

  @doc """
  Render sample content as Phoenix.LiveView.Rendered or HTML-safe iodata.

  ## Parameters

  - `sample` - The sample DTO to render
  - `opts` - Keyword list of rendering options

  ## Options

  - `:mode` - Rendering mode (`:labeling`, `:review`, `:audit`, etc.)
  - `:highlight` - List of artifact IDs to emphasize
  - `:current_user` - User ID for personalization
  - `:preprocessed` - Preprocessed data from `preprocess_sample/1`

  ## Returns

  Phoenix.LiveView.Rendered struct or HTML-safe iodata that can be
  rendered in a LiveView template.

  ## Examples

      render_sample(sample, mode: :labeling)
      render_sample(sample, mode: :review, highlight: ["artifact-1"])
  """
  @callback render_sample(sample :: Sample.t(), opts :: Keyword.t()) ::
              Phoenix.LiveView.Rendered.t() | iodata()

  @doc """
  Return list of asset paths (CSS/JS) required by this component.

  Ingot will include these assets in the page head when this component
  is active. This allows components to bundle their own styling and
  JavaScript without polluting the global asset pipeline.

  ## Returns

  Map with the following keys:

  - `:css` - List of CSS file paths (e.g., `["/assets/my_app/styles.css"]`)
  - `:js` - List of JavaScript file paths (e.g., `["/assets/my_app/app.js"]`)
  - `:hooks` - List of LiveView hook names (atoms) (e.g., `[:MyCustomHook]`)

  ## Examples

      def required_assets do
        %{
          css: ["/assets/cns/narratives.css"],
          js: ["/assets/cns/narrative-tabs.js"],
          hooks: [:NarrativeTabs]
        }
      end

      def required_assets do
        %{css: [], js: [], hooks: []}
      end
  """
  @callback required_assets() :: %{
              css: [String.t()],
              js: [String.t()],
              hooks: [atom()]
            }

  @doc """
  Optional: preprocess sample data before rendering.

  Use this for expensive computations that should be done once when
  the sample is loaded, rather than on every render. The result is
  cached in LiveView assigns and passed to `render_sample/2` via
  the `:preprocessed` option.

  ## Parameters

  - `sample` - The sample DTO to preprocess

  ## Returns

  Map containing preprocessed data that will be cached in assigns.

  ## Examples

      def preprocess_sample(sample) do
        %{
          claims: extract_claims(sample.payload),
          entities: extract_entities(sample.payload),
          complexity_score: calculate_complexity(sample.payload)
        }
      end
  """
  @callback preprocess_sample(sample :: Sample.t()) :: map()

  @optional_callbacks [preprocess_sample: 1]
end
