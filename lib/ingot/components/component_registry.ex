defmodule Ingot.Components.ComponentRegistry do
  @moduledoc """
  Manages dynamic loading and caching of pluggable components.

  This GenServer loads component modules at runtime based on queue
  configuration, verifies they implement the required behaviors,
  and caches them for efficient repeated access.

  ## Component Resolution

  1. Check cache for queue_id
  2. If not cached, fetch queue metadata from AnvilClient
  3. If metadata contains `component_module`, load and verify it
  4. If no component_module or loading fails, return DefaultComponent
  5. Cache the result for future lookups

  ## Usage

      # Get component for a queue
      {:ok, component} = ComponentRegistry.get_component("queue-123")

      # Use the component
      component.render_sample(sample, mode: :labeling)

      # Clear cache (e.g., after deploying new component version)
      ComponentRegistry.clear_cache()
  """

  use GenServer
  require Logger

  alias Ingot.{AnvilClient, Components.DefaultComponent}

  @type component_module :: module()
  @type queue_id :: String.t()
  @type error :: :module_not_found | :invalid_component | term()

  ## Client API

  @doc """
  Start the ComponentRegistry GenServer.

  Typically started as part of the application supervision tree.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get component module for a queue.

  Loads and caches the component on first access. Returns DefaultComponent
  if no custom component is configured or if loading fails.

  ## Examples

      {:ok, component} = ComponentRegistry.get_component("queue-123")
      component.render_sample(sample, [])
  """
  @spec get_component(queue_id) :: {:ok, component_module()} | {:error, error()}
  def get_component(queue_id) do
    GenServer.call(__MODULE__, {:get_component, queue_id})
  end

  @doc """
  Load and verify a component module.

  Can be called with either a string module name or an atom.
  Verifies that the module implements both required behaviors.

  ## Examples

      {:ok, module} = ComponentRegistry.load_component("MyApp.CustomComponent")
      {:ok, module} = ComponentRegistry.load_component(MyApp.CustomComponent)
  """
  @spec load_component(String.t() | atom()) :: {:ok, component_module()} | {:error, error()}
  def load_component(module_name) do
    GenServer.call(__MODULE__, {:load_component, module_name})
  end

  @doc """
  Clear all cached components.

  Useful when deploying new component versions or during testing.

  ## Examples

      :ok = ComponentRegistry.clear_cache()
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    GenServer.call(__MODULE__, :clear_cache)
  end

  @doc """
  Clear cached component for a specific queue.

  ## Examples

      :ok = ComponentRegistry.clear_cache("queue-123")
  """
  @spec clear_cache(queue_id) :: :ok
  def clear_cache(queue_id) do
    GenServer.call(__MODULE__, {:clear_cache, queue_id})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %{components: %{}}}
  end

  @impl true
  def handle_call({:get_component, queue_id}, _from, state) do
    case Map.get(state.components, queue_id) do
      nil ->
        # Not cached - fetch from Anvil and load component
        case fetch_and_load_component(queue_id) do
          {:ok, component} ->
            state = put_in(state.components[queue_id], component)
            {:reply, {:ok, component}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      component ->
        # Already cached
        {:reply, {:ok, component}, state}
    end
  end

  @impl true
  def handle_call({:load_component, module_name}, _from, state) do
    result = do_load_component(module_name)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:clear_cache, _from, _state) do
    {:reply, :ok, %{components: %{}}}
  end

  @impl true
  def handle_call({:clear_cache, queue_id}, _from, state) do
    state = update_in(state.components, &Map.delete(&1, queue_id))
    {:reply, :ok, state}
  end

  ## Private Functions

  defp fetch_and_load_component(queue_id) do
    case AnvilClient.get_next_assignment(queue_id, "component-registry",
           tenant_id: default_tenant_id()
         ) do
      {:ok, assignment} ->
        component_module = get_in(assignment.metadata, ["component_module"])

        if component_module do
          case do_load_component(component_module) do
            {:ok, module} ->
              Logger.info("Loaded component #{inspect(module)} for queue #{queue_id}")

              {:ok, module}

            {:error, reason} ->
              Logger.warning(
                "Failed to load component #{component_module} for queue #{queue_id}: #{inspect(reason)}. Using DefaultComponent."
              )

              {:ok, DefaultComponent}
          end
        else
          # No custom component configured
          {:ok, DefaultComponent}
        end

      {:error, :no_assignments} ->
        # Empty queue - use default component
        {:ok, DefaultComponent}

      {:error, reason} ->
        Logger.error("Failed to fetch queue #{queue_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp do_load_component(nil), do: {:ok, DefaultComponent}

  defp do_load_component(module_name) when is_binary(module_name) do
    # Convert string to atom (only if atom already exists)
    module = String.to_existing_atom("Elixir.#{module_name}")
    do_load_component(module)
  rescue
    ArgumentError ->
      {:error, :module_not_found}
  end

  defp do_load_component(module) when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        # Verify module implements required behaviors
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
    # Get all behavior attributes (there can be multiple @behaviour declarations)
    all_behaviors =
      module.module_info(:attributes)
      |> Enum.filter(fn {key, _value} -> key == :behaviour end)
      |> Enum.flat_map(fn {:behaviour, behaviors} -> behaviors end)

    Ingot.SampleRenderer in all_behaviors and
      Ingot.LabelFormRenderer in all_behaviors
  end

  defp default_tenant_id do
    Application.get_env(:ingot, :default_tenant_id)
  end
end
