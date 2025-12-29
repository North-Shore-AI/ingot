defmodule Ingot.ForgeClient.MockAdapter do
  @moduledoc """
  Mock Forge adapter emitting LabelingIR.Sample structs.
  """

  @behaviour Ingot.ForgeClient

  alias LabelingIR.Sample

  @impl true
  def get_sample(_sample_id, _opts \\ []) do
    sample = %Sample{
      id: "sample-mock",
      tenant_id: "tenant_mock",
      pipeline_id: "pipe-mock",
      payload: %{"headline" => "Mock sample"},
      artifacts: [],
      metadata: %{},
      created_at: DateTime.utc_now()
    }

    {:ok, sample}
  end

  @impl true
  def queue_stats(_opts \\ []) do
    {:ok, %{total: 1, remaining: 1, labeled: 0}}
  end

  @impl true
  def health_check, do: {:ok, :healthy}
end
