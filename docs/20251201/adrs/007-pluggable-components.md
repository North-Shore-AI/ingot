# ADR-007: Pluggable Components

## Status
Accepted

## Context

Ingot must support domain-specific labeling workflows without hardcoding domain logic into the core application. The first major use case is CNS (Critic-Network Synthesis), which requires specialized UI components:

1. **Narrative Display**: Side-by-side view of thesis, antithesis, synthesis narratives (multi-paragraph text with highlighted claims)
2. **Claim Lists**: Interactive table of extracted claims with grounding scores, contradiction flags
3. **SNO Graph Visualization**: Topological graph of synthesis network (nodes = claims, edges = relationships)
4. **Dialectical Schema**: Custom label dimensions (coherence, groundedness, balance, novelty, causal_validity)

**Generalization Requirements:**

Other research projects may need different components:
- **Image Segmentation**: Canvas overlay for polygon annotation
- **Audio Transcription**: Waveform display with timestamped corrections
- **Code Review**: Syntax-highlighted diff viewer with inline comments
- **Medical Imaging**: DICOM viewer with measurement tools

**Current State (v0.1):**
- Generic sample display (JSON pretty-print)
- Fixed label form (generated from schema)
- No extension mechanism for custom components

**Design Constraints:**

1. **No Code Changes to Ingot Core**: Adding a new domain (e.g., medical imaging) should not require modifying Ingot's LiveView code
2. **Runtime Registration**: Components should be registered via configuration, not compile-time dependencies
3. **Type Safety**: Component contracts should be clear (inputs: sample, outputs: rendered HTML)
4. **Isolated Dependencies**: Domain-specific deps (e.g., CNS.SNOParser) should not leak into Ingot
5. **Versioning**: Components should declare compatibility (e.g., "works with Ingot >=1.0")

**Key Questions:**

1. How are components discovered and registered at runtime?
2. What's the contract between Ingot and components (function signature, behavior)?
3. How do components declare dependencies (CSS, JS hooks)?
4. Should components be in-process (Elixir modules) or external (plugins via HTTP)?
5. How to handle component errors without crashing Ingot?

## Decision

**Implement pluggable component system using runtime-registered Elixir modules with behavior contracts. Components declare themselves in queue configuration (Anvil schema), Ingot loads them dynamically via `Code.ensure_loaded/1`. Each component implements `Ingot.SampleRenderer` and `Ingot.LabelFormRenderer` behaviors. Components can bundle CSS/JS via Phoenix component attributes.**

### Architecture

```
┌────────────────────────────────────────────────┐
│         Anvil Queue Configuration              │
│  queue.metadata = %{                           │
│    component_module: "CNS.IngotComponents"    │
│  }                                             │
└────────────┬───────────────────────────────────┘
             │
             ▼
┌────────────────────────────────────────────────┐
│      Ingot.ComponentRegistry (GenServer)       │
│  - load_component("CNS.IngotComponents")       │
│  - verify behavior implementation              │
│  - cache module reference                      │
└────────────┬───────────────────────────────────┘
             │
             ▼
┌────────────────────────────────────────────────┐
│   CNS.IngotComponents (implements behaviors)   │
│  - render_sample(sample, opts)                 │
│  - render_label_form(schema, label_data, opts) │
│  - required_assets() → CSS/JS paths            │
└────────────┬───────────────────────────────────┘
             │
             ▼
┌────────────────────────────────────────────────┐
│      LabelingLive (uses component)             │
│  component = ComponentRegistry.get(queue_id)   │
│  sample_html = component.render_sample(sample) │
│  form_html = component.render_label_form(...)  │
└────────────────────────────────────────────────┘
```

### Component Behaviors

```elixir
defmodule Ingot.SampleRenderer do
  @moduledoc """
  Behavior for custom sample rendering.
  Implement this to provide domain-specific sample visualization.
  """

  alias Ingot.DTO.Sample

  @doc """
  Render sample content as Phoenix.LiveView.Rendered or HTML-safe iodata.

  Options may include:
  - :mode - :labeling | :review | :audit
  - :highlight - list of artifact IDs to emphasize
  - :current_user - user_id for personalization
  """
  @callback render_sample(sample :: Sample.t(), opts :: Keyword.t()) ::
    Phoenix.LiveView.Rendered.t() | iodata()

  @doc """
  Return list of asset paths (CSS/JS) required by this component.
  Ingot will include them in the page head.
  """
  @callback required_assets() :: %{
    css: [String.t()],
    js: [String.t()],
    hooks: [atom()]  # LiveView hook names
  }

  @doc """
  Optional: preprocess sample data before rendering.
  Use for expensive computations (e.g., parsing JSON, extracting claims).
  Result is cached in LiveView assigns.
  """
  @callback preprocess_sample(sample :: Sample.t()) :: map()

  @optional_callbacks [preprocess_sample: 1]
end

defmodule Ingot.LabelFormRenderer do
  @moduledoc """
  Behavior for custom label form rendering.
  Implement this to provide domain-specific input widgets.
  """

  @doc """
  Render label form as Phoenix.LiveView.Rendered or HTML-safe iodata.

  Args:
  - schema: label schema from queue config
  - label_data: current form state (map)
  - opts: rendering options

  Returns: Phoenix component or iodata
  """
  @callback render_label_form(
    schema :: map(),
    label_data :: map(),
    opts :: Keyword.t()
  ) :: Phoenix.LiveView.Rendered.t() | iodata()

  @doc """
  Optional: validate label data before submission.
  Return {:ok, label_data} or {:error, errors}.
  """
  @callback validate_label(label_data :: map(), schema :: map()) ::
    {:ok, map()} | {:error, map()}

  @optional_callbacks [validate_label: 2]
end
```

### Component Registration

**Queue Configuration (in Anvil):**

```elixir
# When creating CNS labeling queue
AnvilClient.create_queue(%{
  name: "CNS Coherence Evaluation",
  label_schema: %{
    dimensions: [
      %{key: "coherence", name: "Coherence", type: "scale", min: 1, max: 5},
      %{key: "groundedness", name: "Groundedness", type: "scale", min: 1, max: 5},
      %{key: "balance", name: "Dialectical Balance", type: "scale", min: 1, max: 5},
      %{key: "notes", name: "Notes", type: "text"}
    ]
  },
  metadata: %{
    component_module: "CNS.IngotComponents",  # Component module name
    component_version: "1.0.0"
  }
})
```

**Component Registry:**

```elixir
defmodule Ingot.ComponentRegistry do
  use GenServer

  @moduledoc """
  Manages dynamic loading and caching of pluggable components.
  """

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    {:ok, %{components: %{}}}
  end

  @doc """
  Load and verify component module for a queue.
  Returns cached reference if already loaded.
  """
  def get_component(queue_id) do
    GenServer.call(__MODULE__, {:get_component, queue_id})
  end

  def handle_call({:get_component, queue_id}, _from, state) do
    case Map.get(state.components, queue_id) do
      nil ->
        # Fetch queue metadata from Anvil
        {:ok, queue} = Ingot.AnvilClient.get_queue(queue_id)
        component_module = queue.metadata["component_module"]

        if component_module do
          case load_component(component_module) do
            {:ok, module} ->
              state = put_in(state.components[queue_id], module)
              {:reply, {:ok, module}, state}

            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        else
          # No custom component, use default
          {:reply, {:ok, Ingot.DefaultComponent}, state}
        end

      module ->
        {:reply, {:ok, module}, state}
    end
  end

  defp load_component(module_name) when is_binary(module_name) do
    module = String.to_existing_atom("Elixir.#{module_name}")
    load_component(module)
  rescue
    ArgumentError -> {:error, :module_not_found}
  end

  defp load_component(module) when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        # Verify behaviors
        if implements_behaviors?(module) do
          {:ok, module}
        else
          {:error, :invalid_component}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp implements_behaviors?(module) do
    behaviors = module.__info__(:attributes)[:behaviour] || []
    Ingot.SampleRenderer in behaviors and Ingot.LabelFormRenderer in behaviors
  end
end
```

### CNS Component Implementation

```elixir
defmodule CNS.IngotComponents do
  @behaviour Ingot.SampleRenderer
  @behaviour Ingot.LabelFormRenderer

  use Phoenix.Component
  import Phoenix.HTML

  @impl Ingot.SampleRenderer
  def render_sample(sample, opts \\ []) do
    mode = Keyword.get(opts, :mode, :labeling)

    assigns = %{
      sample: sample,
      mode: mode,
      narratives: parse_narratives(sample.payload)
    }

    ~H"""
    <div class="cns-sample-display">
      <!-- Narrative Tabs -->
      <div class="narrative-tabs">
        <button class="tab active" data-narrative="thesis">Thesis</button>
        <button class="tab" data-narrative="antithesis">Antithesis</button>
        <button class="tab" data-narrative="synthesis">Synthesis</button>
      </div>

      <!-- Narrative Content -->
      <div class="narrative-content">
        <div class="narrative active" data-narrative="thesis">
          <h3>Thesis (Proposer)</h3>
          <%= raw(@narratives.thesis) %>
        </div>

        <div class="narrative" data-narrative="antithesis">
          <h3>Antithesis (Antagonist)</h3>
          <%= raw(@narratives.antithesis) %>
        </div>

        <div class="narrative" data-narrative="synthesis">
          <h3>Synthesis</h3>
          <%= raw(@narratives.synthesis) %>
        </div>
      </div>

      <!-- Claims Table -->
      <%= if @mode == :review do %>
        <div class="claims-table">
          <h3>Extracted Claims</h3>
          <table>
            <thead>
              <tr>
                <th>Claim</th>
                <th>Grounding</th>
                <th>Contradictions</th>
              </tr>
            </thead>
            <tbody>
              <%= for claim <- @narratives.claims do %>
                <tr>
                  <td><%= claim.text %></td>
                  <td><%= claim.grounding_score %></td>
                  <td><%= claim.contradiction_flags %></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  @impl Ingot.SampleRenderer
  def required_assets do
    %{
      css: ["/assets/cns/narratives.css"],
      js: ["/assets/cns/narrative-tabs.js"],
      hooks: [:NarrativeTabs]
    }
  end

  @impl Ingot.SampleRenderer
  def preprocess_sample(sample) do
    # Parse CNS-specific payload (expensive, done once on mount)
    %{
      narratives: parse_narratives(sample.payload),
      claims: extract_claims(sample.payload),
      topology_metrics: sample.payload["topology_metrics"]
    }
  end

  @impl Ingot.LabelFormRenderer
  def render_label_form(schema, label_data, opts \\ []) do
    assigns = %{schema: schema, label_data: label_data}

    ~H"""
    <div class="cns-label-form">
      <!-- Custom dimension explanations for CNS -->
      <div class="dimension">
        <label for="coherence">
          Coherence
          <span class="help-text">Are the arguments logically connected?</span>
        </label>
        <input type="range" name="label_data[coherence]"
               min="1" max="5"
               value={@label_data[:coherence] || 3}
               phx-change="update_label_data" />
        <span class="value-label">
          <%= coherence_label(@label_data[:coherence] || 3) %>
        </span>
      </div>

      <div class="dimension">
        <label for="groundedness">
          Groundedness
          <span class="help-text">Are claims supported by evidence?</span>
        </label>
        <input type="range" name="label_data[groundedness]"
               min="1" max="5"
               value={@label_data[:groundedness] || 3}
               phx-change="update_label_data" />
        <span class="value-label">
          <%= groundedness_label(@label_data[:groundedness] || 3) %>
        </span>
      </div>

      <div class="dimension">
        <label for="balance">
          Dialectical Balance
          <span class="help-text">Does synthesis integrate both perspectives?</span>
        </label>
        <input type="range" name="label_data[balance]"
               min="1" max="5"
               value={@label_data[:balance] || 3}
               phx-change="update_label_data" />
        <span class="value-label">
          <%= balance_label(@label_data[:balance] || 3) %>
        </span>
      </div>

      <div class="dimension">
        <label for="notes">Notes</label>
        <textarea name="label_data[notes]"
                  placeholder="Any observations about the dialectical process..."
                  phx-change="update_label_data"><%= @label_data[:notes] %></textarea>
      </div>
    </div>
    """
  end

  @impl Ingot.LabelFormRenderer
  def validate_label(label_data, schema) do
    # CNS-specific validation: coherence + groundedness should correlate with balance
    coherence = label_data["coherence"] || 0
    groundedness = label_data["groundedness"] || 0
    balance = label_data["balance"] || 0

    if coherence >= 4 and groundedness >= 4 and balance < 3 do
      {:error, %{
        balance: "High coherence and groundedness usually indicate good balance. Consider re-evaluating."
      }}
    else
      {:ok, label_data}
    end
  end

  # Helper functions
  defp parse_narratives(payload) do
    %{
      thesis: payload["proposer_narrative"],
      antithesis: payload["antagonist_narrative"],
      synthesis: payload["synthesis_narrative"],
      claims: payload["extracted_claims"] || []
    }
  end

  defp coherence_label(1), do: "Incoherent"
  defp coherence_label(2), do: "Weak"
  defp coherence_label(3), do: "Moderate"
  defp coherence_label(4), do: "Strong"
  defp coherence_label(5), do: "Highly Coherent"

  defp groundedness_label(1), do: "Ungrounded"
  defp groundedness_label(2), do: "Weak Evidence"
  defp groundedness_label(3), do: "Moderate Evidence"
  defp groundedness_label(4), do: "Well-Supported"
  defp groundedness_label(5), do: "Fully Grounded"

  defp balance_label(1), do: "Heavily Biased"
  defp balance_label(2), do: "Somewhat Biased"
  defp balance_label(3), do: "Balanced"
  defp balance_label(4), do: "Well-Integrated"
  defp balance_label(5), do: "Perfectly Dialectical"
end
```

### Integration in LabelingLive

```elixir
defmodule IngotWeb.LabelingLive do
  use IngotWeb, :live_view
  alias Ingot.{AnvilClient, ForgeClient, ComponentRegistry}

  def mount(%{"queue_id" => queue_id}, %{"user_id" => user_id}, socket) do
    # Load component for this queue
    {:ok, component} = ComponentRegistry.get_component(queue_id)

    # Fetch assignment and sample
    {:ok, assignment} = AnvilClient.get_next_assignment(queue_id, user_id)
    {:ok, sample} = ForgeClient.get_sample(assignment.sample_id)

    # Preprocess sample if component implements it
    preprocessed =
      if function_exported?(component, :preprocess_sample, 1) do
        component.preprocess_sample(sample)
      else
        %{}
      end

    {:ok, assign(socket,
      component: component,
      sample: sample,
      preprocessed: preprocessed,
      assignment: assignment,
      label_data: %{}
    )}
  end

  def render(assigns) do
    ~H"""
    <div class="labeling-container">
      <!-- Render sample using component -->
      <%= @component.render_sample(@sample, mode: :labeling, preprocessed: @preprocessed) %>

      <!-- Render label form using component -->
      <.form for={@label_data} phx-submit="submit_label">
        <%= @component.render_label_form(@assignment.schema, @label_data) %>

        <div class="actions">
          <button type="submit" class="btn-primary">Submit</button>
        </div>
      </.form>
    </div>
    """
  end

  def handle_event("submit_label", params, socket) do
    %{component: component, assignment: assignment, label_data: label_data} = socket.assigns

    # Validate with component if it implements validation
    case validate_with_component(component, label_data, assignment.schema) do
      {:ok, validated_data} ->
        # Submit to Anvil
        case AnvilClient.submit_label(assignment.id, validated_data) do
          :ok ->
            # Fetch next assignment
            {:noreply, fetch_next_assignment(socket)}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Submission failed: #{reason}")}
        end

      {:error, errors} ->
        {:noreply, assign(socket, validation_errors: errors)}
    end
  end

  defp validate_with_component(component, label_data, schema) do
    if function_exported?(component, :validate_label, 2) do
      component.validate_label(label_data, schema)
    else
      {:ok, label_data}
    end
  end
end
```

### Asset Loading

```elixir
# In IngotWeb.LayoutView
def component_assets(conn) do
  queue_id = get_session(conn, :current_queue_id)

  if queue_id do
    {:ok, component} = Ingot.ComponentRegistry.get_component(queue_id)
    assets = component.required_assets()

    %{
      css: assets.css || [],
      js: assets.js || [],
      hooks: assets.hooks || []
    }
  else
    %{css: [], js: [], hooks: []}
  end
end

# In root.html.heex
<head>
  <!-- Standard Ingot assets -->
  <link rel="stylesheet" href={~p"/assets/app.css"} />
  <script defer src={~p"/assets/app.js"}></script>

  <!-- Component-specific assets -->
  <%= for css_path <- component_assets(@conn).css do %>
    <link rel="stylesheet" href={css_path} />
  <% end %>

  <%= for js_path <- component_assets(@conn).js do %>
    <script defer src={js_path}></script>
  <% end %>
</head>
```

### Default Component (Fallback)

```elixir
defmodule Ingot.DefaultComponent do
  @behaviour Ingot.SampleRenderer
  @behaviour Ingot.LabelFormRenderer

  use Phoenix.Component

  @impl Ingot.SampleRenderer
  def render_sample(sample, _opts) do
    assigns = %{sample: sample}

    ~H"""
    <div class="default-sample-display">
      <h3>Sample <%= @sample.id %></h3>

      <!-- Display artifacts if any -->
      <%= if @sample.artifacts != [] do %>
        <div class="artifacts">
          <%= for artifact <- @sample.artifacts do %>
            <%= case artifact.artifact_type do %>
              <% :image -> %>
                <img src={artifact.url} alt={artifact.filename} />
              <% :json -> %>
                <pre><%= Jason.encode!(artifact.payload, pretty: true) %></pre>
              <% _ -> %>
                <a href={artifact.url}><%= artifact.filename %></a>
            <% end %>
          <% end %>
        </div>
      <% end %>

      <!-- Pretty-print payload -->
      <pre class="sample-payload"><%= Jason.encode!(@sample.payload, pretty: true) %></pre>
    </div>
    """
  end

  @impl Ingot.SampleRenderer
  def required_assets, do: %{css: [], js: [], hooks: []}

  @impl Ingot.LabelFormRenderer
  def render_label_form(schema, label_data, _opts) do
    assigns = %{schema: schema, label_data: label_data}

    ~H"""
    <div class="default-label-form">
      <%= for dimension <- @schema.dimensions do %>
        <div class="dimension">
          <label><%= dimension.name %></label>

          <%= case dimension.type do %>
            <% "scale" -> %>
              <input type="range"
                     name={"label_data[#{dimension.key}]"}
                     min={dimension.min}
                     max={dimension.max}
                     value={@label_data[dimension.key] || dimension.default} />

            <% "text" -> %>
              <textarea name={"label_data[#{dimension.key}]"}><%= @label_data[dimension.key] %></textarea>

            <% "boolean" -> %>
              <input type="checkbox"
                     name={"label_data[#{dimension.key}]"}
                     checked={@label_data[dimension.key]} />

            <% _ -> %>
              <input type="text"
                     name={"label_data[#{dimension.key}]"}
                     value={@label_data[dimension.key]} />
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
```

## Consequences

### Positive

- **Domain Agnostic**: Ingot core remains generic. CNS, medical imaging, code review each provide their own components without modifying Ingot.

- **Runtime Flexibility**: New domains added by deploying component modules and updating queue config. No Ingot recompilation needed.

- **Type Safety**: Behavior contracts ensure components implement required functions. Compile-time checks in component repos.

- **Isolated Dependencies**: CNS components depend on CNS libraries, but Ingot doesn't. Smaller Ingot release artifacts.

- **Reusable Components**: Components can be shared across projects (e.g., "ImageAnnotator" component used by multiple vision projects).

### Negative

- **Runtime Errors**: If component module not found or misbehaves, Ingot must handle gracefully.
  - *Mitigation*: ComponentRegistry validates behaviors on load. Wrap component calls in try/rescue, fall back to DefaultComponent.

- **Versioning Complexity**: Component API changes (e.g., new required callback) break old components.
  - *Mitigation*: Version behaviors (`Ingot.SampleRenderer.V1`). Ingot supports multiple versions, components declare compatibility.

- **Asset Management**: Component CSS/JS must be deployed alongside Ingot.
  - *Mitigation*: Component repos include `priv/static/` with assets. Copy to Ingot's `assets/` during deployment (or serve from CDN).

- **Testing Burden**: Ingot tests must account for different components.
  - *Mitigation*: Use mock component in tests. Document component testing guide (component devs test their own implementations).

### Neutral

- **In-Process vs External**: Current design uses in-process Elixir modules. Could extend to external plugins (HTTP microservices) if needed.
  - Trade-off: In-process is simpler, faster. External allows non-Elixir components (Python scikit-learn UI).

- **Component Discovery**: Currently via queue metadata. Could add registry service or marketplace.
  - Future: Ingot admin UI lists available components for queue creation.

## Implementation Checklist

1. Define `Ingot.SampleRenderer` and `Ingot.LabelFormRenderer` behaviors
2. Implement `Ingot.ComponentRegistry` GenServer
3. Implement `Ingot.DefaultComponent` (fallback)
4. Update `LabelingLive` to use dynamic components
5. Extend Anvil queue schema to include `metadata.component_module`
6. Implement `CNS.IngotComponents` as reference implementation
7. Add component asset loading to layout views
8. Write component developer guide (how to implement behaviors)
9. Add error handling (component load failures, runtime errors)
10. Write tests with mock components

## Component Developer Guide (Summary)

**To create a custom component:**

1. Create Elixir module implementing both behaviors:
   ```elixir
   defmodule MyDomain.IngotComponents do
     @behaviour Ingot.SampleRenderer
     @behaviour Ingot.LabelFormRenderer
     use Phoenix.Component
   end
   ```

2. Implement required callbacks:
   - `render_sample/2`
   - `required_assets/0`
   - `render_label_form/3`

3. Optional: Implement `preprocess_sample/1` for expensive parsing
4. Optional: Implement `validate_label/2` for custom validation

5. Bundle assets in `priv/static/my_domain/`

6. Reference in queue config:
   ```elixir
   metadata: %{component_module: "MyDomain.IngotComponents"}
   ```

7. Test component independently, then integration test with Ingot

## Related ADRs

- ADR-001: Stateless UI Architecture (components don't persist state)
- ADR-002: Client Layer Design (components use ForgeClient/AnvilClient if needed)
- ADR-005: Realtime UX (components can emit LiveView events)
