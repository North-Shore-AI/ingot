defmodule IngotWeb.DashboardLive do
  use IngotWeb, :live_view

  alias Ingot.{AnvilClient, ForgeClient, Progress}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:statistics, AnvilClient.statistics())
      |> assign(:queue_stats, ForgeClient.queue_stats())
      |> assign(:active_labelers, 0)
      |> assign(:last_updated, DateTime.utc_now())

    if connected?(socket) do
      Progress.subscribe_all()
      schedule_refresh()
    end

    {:ok, socket}
  end

  @impl true
  def handle_info({:label_completed, _session_id, _timestamp}, socket) do
    {:noreply, refresh_statistics(socket)}
  end

  def handle_info({:user_joined, _user_id, _timestamp}, socket) do
    {:noreply, update(socket, :active_labelers, &(&1 + 1))}
  end

  def handle_info({:user_left, _user_id, _timestamp}, socket) do
    {:noreply, update(socket, :active_labelers, &max(&1 - 1, 0))}
  end

  def handle_info({:queue_updated, stats, _timestamp}, socket) do
    {:noreply, assign(socket, :queue_stats, stats)}
  end

  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, refresh_statistics(socket)}
  end

  @impl true
  def handle_event("export_csv", _params, socket) do
    case AnvilClient.export_csv() do
      {:ok, csv_data} ->
        socket =
          socket
          |> push_event("download", %{
            filename: "labels_export_#{DateTime.utc_now() |> DateTime.to_unix()}.csv",
            data: csv_data
          })
          |> put_flash(:info, "CSV export ready for download")

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to export CSV")}
    end
  end

  defp refresh_statistics(socket) do
    socket
    |> assign(:statistics, AnvilClient.statistics())
    |> assign(:queue_stats, ForgeClient.queue_stats())
    |> assign(:last_updated, DateTime.utc_now())
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, :timer.seconds(30))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-6xl mx-auto px-4">
        <!-- Header -->
        <div class="bg-white rounded-lg shadow-lg p-6 mb-6">
          <div class="flex justify-between items-center">
            <h1 class="text-3xl font-bold text-gray-800">Labeling Dashboard</h1>
            <div class="flex items-center space-x-4">
              <span class="text-sm text-gray-500">
                Last updated: {format_time(@last_updated)}
              </span>
              <.link
                navigate="/label"
                class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition"
              >
                Start Labeling
              </.link>
            </div>
          </div>
        </div>
        
    <!-- Statistics Grid -->
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-6">
          <!-- Total Labels -->
          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm font-medium text-gray-600">Total Labels</p>
                <p class="text-3xl font-bold text-gray-900">{@statistics.total_labels}</p>
              </div>
              <div class="p-3 bg-blue-100 rounded-full">
                <svg
                  class="w-8 h-8 text-blue-600"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
              </div>
            </div>
          </div>
          <!-- Active Labelers -->
          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm font-medium text-gray-600">Active Labelers</p>
                <p class="text-3xl font-bold text-gray-900">{@active_labelers}</p>
              </div>
              <div class="p-3 bg-green-100 rounded-full">
                <svg
                  class="w-8 h-8 text-green-600"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z"
                  />
                </svg>
              </div>
            </div>
          </div>
          <!-- Queue Remaining -->
          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm font-medium text-gray-600">Remaining</p>
                <p class="text-3xl font-bold text-gray-900">{@queue_stats.remaining}</p>
              </div>
              <div class="p-3 bg-yellow-100 rounded-full">
                <svg
                  class="w-8 h-8 text-yellow-600"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
              </div>
            </div>
          </div>
          <!-- Sessions -->
          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center justify-between">
              <div>
                <p class="text-sm font-medium text-gray-600">Sessions</p>
                <p class="text-3xl font-bold text-gray-900">{@statistics.total_sessions}</p>
              </div>
              <div class="p-3 bg-purple-100 rounded-full">
                <svg
                  class="w-8 h-8 text-purple-600"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2"
                    d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"
                  />
                </svg>
              </div>
            </div>
          </div>
        </div>
        <!-- Rating Averages -->
        <div class="bg-white rounded-lg shadow-lg p-6 mb-6">
          <h2 class="text-xl font-bold text-gray-800 mb-4">Average Ratings</h2>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
            <div>
              <div class="flex justify-between items-center mb-2">
                <span class="text-sm font-medium text-gray-600">Coherence</span>
                <span class="text-lg font-bold text-gray-900">
                  {Float.round(@statistics.avg_coherence, 1)} / 5
                </span>
              </div>
              <div class="w-full bg-gray-200 rounded-full h-2">
                <div
                  class="bg-blue-600 h-2 rounded-full"
                  style={"width: #{@statistics.avg_coherence / 5 * 100}%"}
                >
                </div>
              </div>
            </div>

            <div>
              <div class="flex justify-between items-center mb-2">
                <span class="text-sm font-medium text-gray-600">Grounded</span>
                <span class="text-lg font-bold text-gray-900">
                  {Float.round(@statistics.avg_grounded, 1)} / 5
                </span>
              </div>
              <div class="w-full bg-gray-200 rounded-full h-2">
                <div
                  class="bg-green-600 h-2 rounded-full"
                  style={"width: #{@statistics.avg_grounded / 5 * 100}%"}
                >
                </div>
              </div>
            </div>

            <div>
              <div class="flex justify-between items-center mb-2">
                <span class="text-sm font-medium text-gray-600">Novel</span>
                <span class="text-lg font-bold text-gray-900">
                  {Float.round(@statistics.avg_novel, 1)} / 5
                </span>
              </div>
              <div class="w-full bg-gray-200 rounded-full h-2">
                <div
                  class="bg-purple-600 h-2 rounded-full"
                  style={"width: #{@statistics.avg_novel / 5 * 100}%"}
                >
                </div>
              </div>
            </div>

            <div>
              <div class="flex justify-between items-center mb-2">
                <span class="text-sm font-medium text-gray-600">Balanced</span>
                <span class="text-lg font-bold text-gray-900">
                  {Float.round(@statistics.avg_balanced, 1)} / 5
                </span>
              </div>
              <div class="w-full bg-gray-200 rounded-full h-2">
                <div
                  class="bg-yellow-600 h-2 rounded-full"
                  style={"width: #{@statistics.avg_balanced / 5 * 100}%"}
                >
                </div>
              </div>
            </div>
          </div>
        </div>
        <!-- Performance Metrics -->
        <div class="bg-white rounded-lg shadow-lg p-6">
          <h2 class="text-xl font-bold text-gray-800 mb-4">Performance Metrics</h2>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <p class="text-sm font-medium text-gray-600 mb-2">Average Time per Label</p>
              <p class="text-2xl font-bold text-gray-900">
                {format_duration(@statistics.avg_time_per_label_ms)}
              </p>
            </div>

            <div class="flex justify-end">
              <button
                phx-click="export_csv"
                class="px-6 py-3 bg-green-600 text-white font-semibold rounded-lg hover:bg-green-700 transition-colors shadow"
              >
                Export CSV
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp format_duration(ms) do
    seconds = div(ms, 1000)
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)

    if minutes > 0 do
      "#{minutes}m #{remaining_seconds}s"
    else
      "#{remaining_seconds}s"
    end
  end
end
