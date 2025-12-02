defmodule Ingot.Components.ComponentRegistryTest do
  use ExUnit.Case, async: false

  alias Ingot.Components.{ComponentRegistry, DefaultComponent}
  alias Ingot.DTO.{Assignment, Sample}

  # Valid test component that implements both behaviors
  defmodule ValidComponent do
    @behaviour Ingot.SampleRenderer
    @behaviour Ingot.LabelFormRenderer

    @impl true
    def render_sample(_sample, _opts), do: "<div>Valid</div>"

    @impl true
    def required_assets, do: %{css: [], js: [], hooks: []}

    @impl true
    def render_label_form(_schema, _label_data, _opts), do: "<form>Valid</form>"
  end

  # Invalid component - missing LabelFormRenderer behavior
  defmodule InvalidComponent do
    @behaviour Ingot.SampleRenderer

    @impl true
    def render_sample(_sample, _opts), do: "<div>Invalid</div>"

    @impl true
    def required_assets, do: %{css: [], js: [], hooks: []}
  end

  # Mock AnvilClient that returns queue data with component metadata
  defmodule MockAnvilClientWithComponent do
    @behaviour Ingot.AnvilClient

    @impl true
    def get_next_assignment(queue_id, _user_id) do
      metadata =
        cond do
          queue_id == "queue-with-valid-component" ->
            %{"component_module" => "Ingot.Components.ComponentRegistryTest.ValidComponent"}

          queue_id == "queue-with-invalid-component" ->
            %{"component_module" => "Ingot.Components.ComponentRegistryTest.InvalidComponent"}

          queue_id == "queue-with-nonexistent-component" ->
            %{"component_module" => "NonExistent.Component"}

          true ->
            %{}
        end

      {:ok,
       %Assignment{
         id: "assignment-1",
         queue_id: queue_id,
         sample: %Sample{
           id: "sample-1",
           pipeline_id: "test",
           payload: %{},
           artifacts: [],
           metadata: metadata,
           created_at: DateTime.utc_now()
         },
         schema: %{fields: []},
         existing_labels: [],
         assigned_at: DateTime.utc_now(),
         metadata: metadata
       }}
    end

    # Implement remaining required callbacks with minimal functionality
    @impl true
    def submit_label(_assignment_id, _values), do: :ok

    @impl true
    def get_queue_stats(_queue_id),
      do: {:ok, %Ingot.DTO.QueueStats{total_samples: 0, labeled: 0, remaining: 0}}

    @impl true
    def store_label(_label), do: {:ok, %{}}

    @impl true
    def total_labels, do: 0

    @impl true
    def statistics, do: %{}

    @impl true
    def export_csv, do: {:ok, ""}

    @impl true
    def upsert_user(_attrs), do: {:ok, %{}}

    @impl true
    def get_user_roles(_user_id), do: {:ok, []}

    @impl true
    def check_queue_access(_user_id, _queue_id), do: {:ok, true}

    @impl true
    def create_invite(_attrs), do: {:ok, %{}}

    @impl true
    def get_invite(_code), do: {:error, :not_found}

    @impl true
    def redeem_invite(_code, _user_attrs), do: {:error, :not_found}

    @impl true
    def health_check, do: {:ok, :healthy}
  end

  setup do
    # Stop ComponentRegistry if it's already running (from Application)
    if Process.whereis(ComponentRegistry) do
      Supervisor.terminate_child(Ingot.Supervisor, ComponentRegistry)
      Supervisor.delete_child(Ingot.Supervisor, ComponentRegistry)
    end

    # Start ComponentRegistry for tests
    start_supervised!({ComponentRegistry, []})

    # Configure mock adapter
    original_adapter = Application.get_env(:ingot, :anvil_client_adapter)
    Application.put_env(:ingot, :anvil_client_adapter, MockAnvilClientWithComponent)

    on_exit(fn ->
      if original_adapter do
        Application.put_env(:ingot, :anvil_client_adapter, original_adapter)
      else
        Application.delete_env(:ingot, :anvil_client_adapter)
      end
    end)

    :ok
  end

  describe "get_component/1" do
    test "returns DefaultComponent when no component_module in metadata" do
      queue_id = "queue-without-component"

      assert {:ok, component} = ComponentRegistry.get_component(queue_id)
      assert component == DefaultComponent
    end

    test "loads and caches valid component" do
      queue_id = "queue-with-valid-component"

      # First call - loads the component
      assert {:ok, component} = ComponentRegistry.get_component(queue_id)
      assert component == ValidComponent

      # Second call - returns cached component
      assert {:ok, ^component} = ComponentRegistry.get_component(queue_id)
    end

    @tag capture_log: true
    test "returns DefaultComponent for invalid component (missing behaviors)" do
      queue_id = "queue-with-invalid-component"

      # When a component fails to load, we fall back to DefaultComponent
      assert {:ok, component} = ComponentRegistry.get_component(queue_id)
      assert component == DefaultComponent
    end

    @tag capture_log: true
    test "returns DefaultComponent for nonexistent component module" do
      queue_id = "queue-with-nonexistent-component"

      # When a component module doesn't exist, we fall back to DefaultComponent
      assert {:ok, component} = ComponentRegistry.get_component(queue_id)
      assert component == DefaultComponent
    end

    test "caches component per queue_id" do
      queue_id1 = "queue-with-valid-component"
      queue_id2 = "queue-without-component"

      # Load different components for different queues
      {:ok, component1} = ComponentRegistry.get_component(queue_id1)
      {:ok, component2} = ComponentRegistry.get_component(queue_id2)

      assert component1 == ValidComponent
      assert component2 == DefaultComponent

      # Verify cache works for each queue
      state = :sys.get_state(ComponentRegistry)
      assert Map.get(state.components, queue_id1) == ValidComponent
      assert Map.get(state.components, queue_id2) == DefaultComponent
    end
  end

  describe "load_component/1" do
    test "loads valid component module by string name" do
      module_name = "Ingot.Components.ComponentRegistryTest.ValidComponent"

      assert {:ok, ValidComponent} = ComponentRegistry.load_component(module_name)
    end

    test "loads valid component module by atom" do
      assert {:ok, ValidComponent} = ComponentRegistry.load_component(ValidComponent)
    end

    test "returns error for module that doesn't implement both behaviors" do
      module_name = "Ingot.Components.ComponentRegistryTest.InvalidComponent"

      assert {:error, :invalid_component} = ComponentRegistry.load_component(module_name)
    end

    test "returns error for nonexistent module" do
      assert {:error, :module_not_found} =
               ComponentRegistry.load_component("NonExistent.Module")
    end
  end

  describe "clear_cache/0" do
    test "clears all cached components" do
      queue_id = "queue-with-valid-component"

      # Load and cache a component
      {:ok, _component} = ComponentRegistry.get_component(queue_id)

      state_before = :sys.get_state(ComponentRegistry)
      assert map_size(state_before.components) > 0

      # Clear the cache
      :ok = ComponentRegistry.clear_cache()

      state_after = :sys.get_state(ComponentRegistry)
      assert map_size(state_after.components) == 0
    end
  end

  describe "clear_cache/1" do
    test "clears cached component for specific queue_id" do
      queue_id1 = "queue-with-valid-component"
      queue_id2 = "queue-without-component"

      # Load and cache components for two queues
      {:ok, _} = ComponentRegistry.get_component(queue_id1)
      {:ok, _} = ComponentRegistry.get_component(queue_id2)

      state_before = :sys.get_state(ComponentRegistry)
      assert map_size(state_before.components) == 2

      # Clear cache for only one queue
      :ok = ComponentRegistry.clear_cache(queue_id1)

      state_after = :sys.get_state(ComponentRegistry)
      assert map_size(state_after.components) == 1
      assert Map.has_key?(state_after.components, queue_id2)
      refute Map.has_key?(state_after.components, queue_id1)
    end
  end
end
