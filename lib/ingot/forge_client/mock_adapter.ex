defmodule Ingot.ForgeClient.MockAdapter do
  @moduledoc """
  Mock adapter for ForgeClient used in testing.

  Returns realistic test data without requiring a running Forge instance.
  Supports both new DTO-based API and legacy API for backward compatibility.
  """

  @behaviour Ingot.ForgeClient

  alias Ingot.DTO.Sample

  @impl true
  def get_sample(sample_id) do
    # For specific test IDs, always return success to allow deterministic testing
    # For other IDs, occasionally return errors to exercise error handling paths
    if String.starts_with?(sample_id, "test-") do
      {:ok, build_sample(sample_id)}
    else
      case :rand.uniform(10) do
        10 ->
          {:error, :not_found}

        _ ->
          {:ok, build_sample(sample_id)}
      end
    end
  end

  defp build_sample(sample_id) do
    %Sample{
      id: sample_id,
      pipeline_id: "test_pipeline",
      payload: %{
        narrative_a:
          "Narrative A presents a perspective focusing on economic growth and technological innovation as primary drivers of progress.",
        narrative_b:
          "Narrative B emphasizes environmental sustainability and social equity as essential foundations for long-term prosperity.",
        synthesis:
          "A balanced approach recognizes that economic growth and environmental sustainability are not mutually exclusive but rather interdependent."
      },
      artifacts: [],
      metadata: %{
        model: "gpt-4",
        temperature: 0.7,
        generated_at: DateTime.utc_now()
      },
      created_at: DateTime.utc_now()
    }
  end

  @impl true
  def get_artifacts(_sample_id) do
    # Most samples have no artifacts in testing
    {:ok, []}
  end

  @impl true
  def queue_stats do
    {:ok,
     %{
       total: 500,
       completed: 47,
       remaining: 453
     }}
  end

  # Legacy API implementation

  @impl true
  def fetch_next_sample(user_id) do
    {:ok,
     %{
       id: "sample-#{:rand.uniform(1000)}",
       user_id: user_id,
       narrative_a:
         "Narrative A presents a perspective focusing on economic growth and technological innovation as primary drivers of progress.",
       narrative_b:
         "Narrative B emphasizes environmental sustainability and social equity as essential foundations for long-term prosperity.",
       synthesis:
         "A balanced approach recognizes that economic growth and environmental sustainability are not mutually exclusive but rather interdependent. Technological innovation can drive both economic advancement and ecological preservation when directed toward sustainable practices. Social equity ensures that the benefits of progress are shared broadly, creating stable foundations for continued development.",
       metadata: %{
         generated_at: DateTime.utc_now(),
         model: "gpt-4",
         temperature: 0.7
       }
     }}
  end

  @impl true
  def skip_sample(_sample_id, _user_id) do
    :ok
  end

  @doc """
  Generate new batch of samples (mock implementation).
  """
  def generate_batch(count) do
    {:ok, count}
  end
end
