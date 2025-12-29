defmodule IngotWeb.DashboardLive do
  use IngotWeb, :live_view

  alias Ingot.AnvilClient

  @impl true
  def mount(_params, session, socket) do
    tenant_id = Map.get(session, "tenant_id") || Application.get_env(:ingot, :default_tenant_id)

    {:ok,
     socket
     |> assign(:queue_stats, load_queue_stats(tenant_id))
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
              navigate="/queues/queue-news/label"
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

  defp load_queue_stats(tenant_id) do
    case AnvilClient.get_queue_stats("default", tenant_id: tenant_id) do
      {:ok, stats} -> Map.merge(%{remaining: 0, labeled: 0}, stats)
      _ -> %{remaining: 0, labeled: 0}
    end
  end
end
