defmodule IngotWeb.LabelingLive do
  use IngotWeb, :live_view

  alias Ingot.{ForgeClient, AnvilClient, Progress}
  alias IngotWeb.Live.Components.{SampleComponent, LabelFormComponent, ProgressComponent}

  @impl true
  def mount(_params, session, socket) do
    user_id = session["user_id"] || generate_user_id()
    session_id = generate_session_id()

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:session_id, session_id)
      |> assign(:session_started_at, DateTime.utc_now())
      |> assign(:current_sample, nil)
      |> assign(:ratings, %{coherence: nil, grounded: nil, novel: nil, balanced: nil})
      |> assign(:notes, "")
      |> assign(:timer_started_at, nil)
      |> assign(:labels_this_session, 0)
      |> assign(:total_labels, AnvilClient.total_labels())
      |> assign(:active_labelers, 1)
      |> assign(:queue_stats, ForgeClient.queue_stats())
      |> assign(:focused_dimension, :coherence)

    if connected?(socket) do
      Progress.subscribe_all()
      Progress.broadcast_user_joined(user_id)
      {:ok, fetch_next_sample(socket)}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("rate", %{"dimension" => dimension, "value" => value}, socket) do
    dimension_atom = String.to_existing_atom(dimension)
    rating_value = String.to_integer(value)

    socket =
      socket
      |> update(:ratings, &Map.put(&1, dimension_atom, rating_value))
      |> maybe_advance_focus(dimension_atom)

    {:noreply, socket}
  end

  def handle_event("update_notes", %{"value" => notes}, socket) do
    {:noreply, assign(socket, :notes, notes)}
  end

  def handle_event("submit", _params, socket) do
    if all_ratings_complete?(socket.assigns.ratings) do
      socket = submit_label(socket)
      {:noreply, socket}
    else
      socket = put_flash(socket, :error, "Please complete all ratings before submitting")
      {:noreply, socket}
    end
  end

  def handle_event("skip", _params, socket) do
    if socket.assigns.current_sample do
      ForgeClient.skip_sample(socket.assigns.current_sample.id, socket.assigns.user_id)
    end

    {:noreply, fetch_next_sample(socket)}
  end

  def handle_event("quit", _params, socket) do
    Progress.broadcast_user_left(socket.assigns.user_id)
    {:noreply, push_navigate(socket, to: "/")}
  end

  @impl true
  def handle_info({:label_completed, _session_id, _timestamp}, socket) do
    {:noreply, assign(socket, :total_labels, AnvilClient.total_labels())}
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

  @impl true
  def terminate(_reason, socket) do
    Progress.broadcast_user_left(socket.assigns.user_id)
    :ok
  end

  # Private functions

  defp fetch_next_sample(socket) do
    case ForgeClient.fetch_next_sample(socket.assigns.user_id) do
      {:ok, sample} ->
        socket
        |> assign(:current_sample, sample)
        |> assign(:timer_started_at, DateTime.utc_now())
        |> assign(:ratings, %{coherence: nil, grounded: nil, novel: nil, balanced: nil})
        |> assign(:notes, "")
        |> assign(:focused_dimension, :coherence)

      {:error, :queue_empty} ->
        push_navigate(socket, to: "/")

      {:error, _reason} ->
        put_flash(socket, :error, "Failed to fetch next sample")
    end
  end

  defp submit_label(socket) do
    time_spent_ms =
      DateTime.diff(DateTime.utc_now(), socket.assigns.timer_started_at, :millisecond)

    label = %{
      sample_id: socket.assigns.current_sample.id,
      session_id: socket.assigns.session_id,
      user_id: socket.assigns.user_id,
      ratings: socket.assigns.ratings,
      notes: socket.assigns.notes,
      time_spent_ms: time_spent_ms,
      labeled_at: DateTime.utc_now()
    }

    case AnvilClient.store_label(label) do
      {:ok, _stored_label} ->
        Progress.broadcast_label_completed(socket.assigns.session_id)

        socket
        |> update(:labels_this_session, &(&1 + 1))
        |> put_flash(:info, "Label saved successfully")
        |> fetch_next_sample()

      {:error, _reason} ->
        put_flash(socket, :error, "Failed to save label. Please try again.")
    end
  end

  defp all_ratings_complete?(ratings) do
    Enum.all?([:coherence, :grounded, :novel, :balanced], fn dimension ->
      Map.get(ratings, dimension) != nil
    end)
  end

  defp maybe_advance_focus(socket, current_dimension) do
    next_dimension =
      case current_dimension do
        :coherence -> :grounded
        :grounded -> :novel
        :novel -> :balanced
        :balanced -> :balanced
      end

    assign(socket, :focused_dimension, next_dimension)
  end

  defp generate_user_id do
    "user-#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}"
  end

  defp generate_session_id do
    "session-#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-4xl mx-auto px-4">
        <div class="bg-white rounded-lg shadow-lg overflow-hidden">
          <!-- Header -->
          <div class="bg-blue-600 text-white px-6 py-4 flex justify-between items-center">
            <h1 class="text-2xl font-bold">Ingot Labeler</h1>
            <div class="space-x-4">
              <button
                phx-click="skip"
                class="px-4 py-2 bg-blue-500 hover:bg-blue-400 rounded transition"
              >
                Skip
              </button>
              <button
                phx-click="quit"
                class="px-4 py-2 bg-red-500 hover:bg-red-400 rounded transition"
              >
                Quit
              </button>
            </div>
          </div>
          
    <!-- Main Content -->
          <div class="p-6 space-y-6">
            <%= if @current_sample do %>
              <.live_component
                module={SampleComponent}
                id="sample-display"
                sample={@current_sample}
              />

              <.live_component
                module={LabelFormComponent}
                id="label-form"
                ratings={@ratings}
                notes={@notes}
                focused_dimension={@focused_dimension}
              />
            <% else %>
              <div class="text-center py-12 text-gray-500">
                <p class="text-xl">Loading next sample...</p>
              </div>
            <% end %>
            
    <!-- Progress Footer -->
            <.live_component
              module={ProgressComponent}
              id="progress-display"
              labels_this_session={@labels_this_session}
              total_labels={@total_labels}
              queue_stats={@queue_stats}
              active_labelers={@active_labelers}
            />
          </div>
        </div>
        
    <!-- Keyboard Shortcuts Help -->
        <div class="mt-6 text-center text-sm text-gray-600">
          <p>
            Press <kbd class="px-2 py-1 bg-gray-200 rounded">?</kbd> for keyboard shortcuts
          </p>
        </div>
      </div>
    </div>
    """
  end
end
