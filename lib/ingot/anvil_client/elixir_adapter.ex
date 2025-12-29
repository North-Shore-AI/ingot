defmodule Ingot.AnvilClient.ElixirAdapter do
  @moduledoc """
  Placeholder adapter for in-process Anvil integration.
  """

  @behaviour Ingot.AnvilClient

  @impl true
  def get_next_assignment(_queue_id, _user_id, _opts \\ []), do: {:error, :not_available}

  @impl true
  def submit_label(_assignment_id, label, _opts \\ []), do: {:ok, label}

  @impl true
  def get_queue_stats(_queue_id, _opts \\ []), do: {:ok, %{}}

  @impl true
  def check_queue_access(_user_id, _queue_id, _opts \\ []), do: {:ok, true}

  @impl true
  def health_check, do: {:ok, :healthy}
end
