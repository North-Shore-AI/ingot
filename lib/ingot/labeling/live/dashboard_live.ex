defmodule Ingot.Labeling.DashboardLive do
  @moduledoc """
  Host-agnostic LiveView for labeling dashboard.

  Displays queue statistics and provides navigation to labeling interface.
  This LiveView is portable and can be mounted in any Phoenix application.
  """

  use Phoenix.LiveView

  @impl true
  def mount(_params, session, socket) do
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

    # Get default queue_id from config
    queue_id = Map.get(config, :default_queue_id, "default")

    {:ok,
     socket
     |> assign(:backend, backend)
     |> assign(:tenant_id, tenant_id)
     |> assign(:queue_id, queue_id)
     |> assign(:config, config)
     |> assign(:queue_stats, load_queue_stats(backend, queue_id, tenant_id))
     |> assign(:page_title, "Labeling Dashboard")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-4xl mx-auto px-4">
        <div class="bg-white rounded-lg shadow p-6 mb-6">
          <div class="flex justify-between items-center">
            <h1 class="text-2xl font-bold text-gray-800">Labeling Dashboard</h1>
            <.link
              navigate={labeling_path(@queue_id)}
              class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition"
            >
              Start Labeling
            </.link>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div class="bg-white rounded-lg shadow p-4">
            <p class="text-sm text-gray-600">Remaining</p>
            <p class="text-3xl font-semibold text-gray-900">{@queue_stats.remaining}</p>
          </div>
          <div class="bg-white rounded-lg shadow p-4">
            <p class="text-sm text-gray-600">Labeled</p>
            <p class="text-3xl font-semibold text-gray-900">{@queue_stats.labeled}</p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp load_queue_stats(backend, queue_id, tenant_id) do
    case backend.get_queue_stats(queue_id, tenant_id: tenant_id) do
      {:ok, stats} -> Map.merge(%{remaining: 0, labeled: 0}, stats)
      _ -> %{remaining: 0, labeled: 0}
    end
  end

  # Helper to construct labeling path (host app determines the base path)
  # This uses relative navigation from the dashboard
  defp labeling_path(queue_id) do
    "./queues/#{queue_id}/label"
  end
end
