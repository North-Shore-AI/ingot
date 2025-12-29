defmodule Ingot.Labeling.AnvilClientBackend do
  @moduledoc """
  Backend adapter that wraps `Ingot.AnvilClient` to implement the
  `Ingot.Labeling.Backend` behaviour.

  This allows the existing ingot app to use its current AnvilClient
  while also being compatible with the new composable labeling interface.

  ## Usage

  In the original ingot app router:

      labeling_routes "/labeling",
        config: %{backend: Ingot.Labeling.AnvilClientBackend}
  """

  @behaviour Ingot.Labeling.Backend

  alias Ingot.AnvilClient

  @impl true
  def get_next_assignment(queue_id, user_id, opts) do
    AnvilClient.get_next_assignment(queue_id, user_id, opts)
  end

  @impl true
  def submit_label(assignment_id, label, opts) do
    AnvilClient.submit_label(assignment_id, label, opts)
  end

  @impl true
  def get_queue_stats(queue_id, opts) do
    AnvilClient.get_queue_stats(queue_id, opts)
  end

  @impl true
  def check_queue_access(user_id, queue_id, opts) do
    AnvilClient.check_queue_access(user_id, queue_id, opts)
  end
end
