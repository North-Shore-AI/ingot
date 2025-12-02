defmodule IngotWeb.Live.Components.LabelFormComponent do
  use IngotWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6" id="label-form">
      <h2 class="text-xl font-semibold text-gray-700">YOUR RATING:</h2>
      
    <!-- Rating Dimensions -->
      <div class="space-y-4">
        <%= for {dimension, label, description} <- dimensions() do %>
          <div class={"border rounded-lg p-4 #{if @focused_dimension == dimension, do: "border-blue-500 bg-blue-50", else: "border-gray-200"}"}>
            <div class="flex items-center justify-between mb-2">
              <div>
                <span class="font-semibold text-gray-700">{label}:</span>
                <span class="text-sm text-gray-500 ml-2">{description}</span>
              </div>
              <%= if @focused_dimension == dimension do %>
                <span class="text-xs text-blue-600 font-medium">Press 1-5</span>
              <% end %>
            </div>

            <div class="flex space-x-2">
              <%= for value <- 1..5 do %>
                <button
                  type="button"
                  phx-click="rate"
                  phx-value-dimension={dimension}
                  phx-value-value={value}
                  class={[
                    "flex-1 py-3 rounded-lg font-semibold transition-all",
                    if(Map.get(@ratings, dimension) == value,
                      do: "bg-blue-600 text-white shadow-lg",
                      else: "bg-gray-100 text-gray-700 hover:bg-gray-200"
                    )
                  ]}
                  data-rating={value}
                  data-dimension={dimension}
                  data-selected={Map.get(@ratings, dimension) == value}
                >
                  {value}
                </button>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
      
    <!-- Notes -->
      <div>
        <label for="notes" class="block text-sm font-medium text-gray-700 mb-2">
          Notes (optional):
        </label>
        <textarea
          id="notes"
          name="notes"
          rows="3"
          phx-change="update_notes"
          phx-value-value={@notes}
          class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
          placeholder="Add any additional observations or comments..."
        ><%= @notes %></textarea>
      </div>
      
    <!-- Submit Button -->
      <div class="flex justify-end">
        <button
          type="button"
          phx-click="submit"
          id="submit-button"
          class="px-8 py-3 bg-green-600 text-white font-semibold rounded-lg hover:bg-green-700 transition-colors shadow-lg"
        >
          Submit & Next →
        </button>
      </div>
    </div>
    """
  end

  defp dimensions do
    [
      {:coherence, "Coherence", "How well does the synthesis integrate both narratives?"},
      {:grounded, "Grounded", "Is the synthesis supported by the source narratives?"},
      {:novel, "Novel", "Does the synthesis add new insights beyond simple summary?"},
      {:balanced, "Balanced", "Does the synthesis give fair weight to both perspectives?"}
    ]
  end
end
