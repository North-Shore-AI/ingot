defmodule Ingot.ForgeClient.ElixirAdapter do
  @moduledoc """
  Placeholder adapter for in-process Forge integration.
  """

  @behaviour Ingot.ForgeClient

  @impl true
  def get_sample(_sample_id, _opts \\ []), do: {:error, :not_available}

  @impl true
  def queue_stats(_opts \\ []), do: {:ok, %{total: 0, remaining: 0, labeled: 0}}

  @impl true
  def health_check, do: {:ok, :healthy}
end
