defmodule Ingot.Labeling.LabelingLive do
  @moduledoc """
  Host-agnostic LiveView for labeling interface.

  This LiveView is designed to be portable and can be mounted in any Phoenix
  application using the `Ingot.Labeling.Router.labeling_routes/2` macro.

  Configuration is injected via session (from the router macro), and all data
  operations are delegated to a backend module implementing `Ingot.Labeling.Backend`.
  """

  use Phoenix.LiveView

  alias Ingot.Components.DefaultComponent
  alias LabelingIR.{Assignment, Label, Schema}

  @impl true
  def mount(%{"queue_id" => queue_id}, session, socket) do
    # Extract configuration from session (injected by router macro)
    config = session["labeling_config"] || %{}
    backend = Map.get(config, :backend)

    unless backend do
      raise ArgumentError, """
      Labeling backend not configured. Ensure you pass a :backend in the config option:

        labeling_routes "/labeling",
          config: %{backend: MyApp.LabelingBackend}
      """
    end

    # Get tenant_id from config or session
    tenant_id = Map.get(config, :tenant_id) || session["tenant_id"] || "dev"

    # Get user_id from session (set by on_mount hooks)
    user_id = session["user_id"] || session["current_user_id"] || generate_user_id()

    socket =
      socket
      |> assign(:backend, backend)
      |> assign(:queue_id, queue_id)
      |> assign(:tenant_id, tenant_id)
      |> assign(:user_id, user_id)
      |> assign(:config, config)
      |> assign(:assignment, nil)
      |> assign(:component, DefaultComponent)
      |> assign(:component_assets, %{css: [], js: [], hooks: []})
      |> assign(:preprocessed, nil)
      |> assign(:label_data, %{})
      |> assign(:error, nil)

    {:ok, fetch_assignment(socket)}
  end

  @impl true
  def handle_event("update_label", %{"label_data" => label_data}, socket) do
    {:noreply, assign(socket, :label_data, normalize_label_data(label_data))}
  end

  @impl true
  def handle_event("submit_label", params, socket) do
    label_data = normalize_label_data(params["label_data"] || %{})

    case build_label(socket.assigns.assignment, socket.assigns, label_data) do
      {:ok, label} ->
        # Use backend to submit label
        case socket.assigns.backend.submit_label(
               socket.assigns.assignment.id,
               label,
               tenant_id: socket.assigns.tenant_id
             ) do
          {:ok, _stored} ->
            socket =
              socket
              |> assign(:label_data, %{})
              |> put_flash(:info, "Label submitted")
              |> fetch_assignment()

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, assign(socket, :error, inspect(reason))}
        end

      {:error, reason} ->
        {:noreply, assign(socket, :error, inspect(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="labeling-shell">
      <%= if @assignment do %>
        <div id="assignment-meta" data-queue-id={@queue_id} data-tenant-id={@tenant_id}></div>
        {@component.render_sample(@assignment.sample, mode: :labeling, preprocessed: @preprocessed)}
        {@component.render_label_form(@assignment.schema, @label_data, show_help: false)}
      <% else %>
        <div id="empty-state">No assignment available</div>
      <% end %>

      <%= if @error do %>
        <div id="error" role="alert">{@error}</div>
      <% end %>
    </div>
    """
  end

  defp fetch_assignment(socket) do
    # Use backend to get next assignment
    case socket.assigns.backend.get_next_assignment(
           socket.assigns.queue_id,
           socket.assigns.user_id,
           tenant_id: socket.assigns.tenant_id
         ) do
      {:ok, %Assignment{} = assignment} ->
        component = resolve_component(assignment)
        assets = safe_assets(component)
        preprocessed = maybe_preprocess(component, assignment.sample)
        label_data = initial_label_data(assignment.schema)

        socket
        |> assign(:assignment, assignment)
        |> assign(:component, component)
        |> assign(:component_assets, assets)
        |> assign(:preprocessed, preprocessed)
        |> assign(:label_data, label_data)
        |> assign(:error, nil)

      {:error, reason} ->
        assign(socket, :error, inspect(reason))
    end
  end

  defp resolve_component(%Assignment{} = assignment) do
    module_name =
      get_in(assignment.metadata, ["component_module"]) ||
        get_in(assignment.metadata, [:component_module]) ||
        assignment.schema.component_module

    module =
      cond do
        is_atom(module_name) -> module_name
        is_binary(module_name) -> Module.concat([module_name])
        true -> nil
      end

    case module do
      nil ->
        DefaultComponent

      mod when is_atom(mod) ->
        case Code.ensure_loaded(mod) do
          {:module, ^mod} -> mod
          _ -> DefaultComponent
        end
    end
  end

  defp safe_assets(component) do
    if function_exported?(component, :required_assets, 0) do
      component.required_assets() || %{css: [], js: [], hooks: []}
    else
      %{css: [], js: [], hooks: []}
    end
  end

  defp maybe_preprocess(component, sample) do
    if function_exported?(component, :preprocess_sample, 1) do
      component.preprocess_sample(sample)
    else
      nil
    end
  end

  defp initial_label_data(%Schema{} = schema) do
    schema.fields
    |> Enum.reduce(%{}, fn field, acc ->
      if field.default != nil do
        Map.put(acc, field.name, field.default)
      else
        acc
      end
    end)
  end

  defp normalize_label_data(params) do
    params
    |> Enum.map(fn {k, v} -> {normalize_key(k), v} end)
    |> Map.new()
  end

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: key

  defp build_label(nil, _assigns, _data), do: {:error, :no_assignment}

  defp build_label(assignment, assigns, values) do
    {:ok,
     %Label{
       id: generate_id(),
       assignment_id: assignment.id,
       sample_id: assignment.sample.id,
       queue_id: assignment.queue_id,
       tenant_id: assigns.tenant_id,
       namespace: assignment.namespace || assignment.sample.namespace,
       user_id: assigns.user_id,
       values: values,
       time_spent_ms: Map.get(assigns, :time_spent_ms, 0),
       created_at: DateTime.utc_now(),
       lineage_ref: assignment.lineage_ref,
       metadata: %{}
     }}
  end

  defp generate_user_id do
    "user-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
  end

  defp generate_id do
    "lbl-" <> Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)
  end
end
