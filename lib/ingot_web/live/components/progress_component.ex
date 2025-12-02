defmodule IngotWeb.Live.Components.ProgressComponent do
  use IngotWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="border-t border-gray-200 pt-4 mt-6">
      <div class="space-y-3">
        <!-- Session Progress -->
        <div>
          <div class="flex justify-between items-center mb-1">
            <span class="text-sm font-medium text-gray-600">Session Progress:</span>
            <span class="text-sm font-semibold text-gray-800">
              {@labels_this_session} labeled
            </span>
          </div>
          <div class="w-full bg-gray-200 rounded-full h-2">
            <div
              class="bg-blue-600 h-2 rounded-full transition-all duration-300"
              style={"width: #{session_progress_percent(assigns)}%"}
            >
            </div>
          </div>
        </div>
        
    <!-- Overall Progress -->
        <div>
          <div class="flex justify-between items-center mb-1">
            <span class="text-sm font-medium text-gray-600">Overall Progress:</span>
            <span class="text-sm font-semibold text-gray-800">
              {@total_labels} / {@queue_stats.total} labeled ({overall_progress_percent(assigns)}%)
            </span>
          </div>
          <div class="w-full bg-gray-200 rounded-full h-2">
            <div
              class="bg-green-600 h-2 rounded-full transition-all duration-300"
              style={"width: #{overall_progress_percent(assigns)}%"}
            >
            </div>
          </div>
        </div>
        
    <!-- Statistics Row -->
        <div class="flex justify-between text-sm text-gray-600 pt-2">
          <span>
            <span class="font-medium">{@active_labelers}</span>
            active {if @active_labelers == 1, do: "labeler", else: "labelers"}
          </span>
          <span>
            <span class="font-medium">{@queue_stats.remaining}</span> samples remaining
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp session_progress_percent(assigns) do
    if assigns.labels_this_session > 0 do
      min(100, assigns.labels_this_session * 2)
    else
      0
    end
  end

  defp overall_progress_percent(assigns) do
    if assigns.queue_stats.total > 0 do
      Float.round(assigns.total_labels / assigns.queue_stats.total * 100, 1)
    else
      0
    end
  end
end
