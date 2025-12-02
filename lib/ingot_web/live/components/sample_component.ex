defmodule IngotWeb.Live.Components.SampleComponent do
  use IngotWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <!-- Narrative A -->
      <div>
        <h2 class="text-lg font-semibold text-gray-700 mb-2">NARRATIVE A:</h2>
        <div class="bg-blue-50 border border-blue-200 rounded-lg p-4 max-h-48 overflow-y-auto">
          <p class="text-gray-800 leading-relaxed">{@sample.narrative_a}</p>
        </div>
      </div>
      
    <!-- Narrative B -->
      <div>
        <h2 class="text-lg font-semibold text-gray-700 mb-2">NARRATIVE B:</h2>
        <div class="bg-green-50 border border-green-200 rounded-lg p-4 max-h-48 overflow-y-auto">
          <p class="text-gray-800 leading-relaxed">{@sample.narrative_b}</p>
        </div>
      </div>
      
    <!-- Synthesis -->
      <div>
        <h2 class="text-lg font-semibold text-gray-700 mb-2">SYNTHESIS:</h2>
        <div class="bg-purple-50 border border-purple-200 rounded-lg p-4 max-h-48 overflow-y-auto">
          <p class="text-gray-800 leading-relaxed">{@sample.synthesis}</p>
        </div>
      </div>
    </div>
    """
  end
end
