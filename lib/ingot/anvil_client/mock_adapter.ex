defmodule Ingot.AnvilClient.MockAdapter do
  @moduledoc """
  Mock adapter for AnvilClient used in testing.

  Returns realistic test data without requiring a running Anvil instance.
  Supports both new DTO-based API and legacy API for backward compatibility.
  """

  @behaviour Ingot.AnvilClient

  alias Ingot.DTO.{Assignment, QueueStats, Sample}

  @impl true
  def get_next_assignment(queue_id, _user_id) do
    # For specific test queue IDs, always return success to allow deterministic testing
    # For other IDs, occasionally return errors to exercise error handling paths
    if String.starts_with?(queue_id, "queue-") do
      {:ok, build_assignment(queue_id)}
    else
      case :rand.uniform(10) do
        10 ->
          {:error, :no_assignments}

        _ ->
          {:ok, build_assignment(queue_id)}
      end
    end
  end

  defp build_assignment(queue_id) do
    %Assignment{
      id: Ecto.UUID.generate(),
      queue_id: queue_id,
      sample: %Sample{
        id: "sample-#{:rand.uniform(1000)}",
        pipeline_id: "test_pipeline",
        payload: %{
          narrative_a:
            "Narrative A presents a perspective focusing on economic growth and technological innovation.",
          narrative_b: "Narrative B emphasizes environmental sustainability and social equity.",
          synthesis:
            "A balanced approach recognizes that both perspectives are necessary for sustainable development."
        },
        artifacts: [],
        metadata: %{model: "test", temperature: 0.7},
        created_at: DateTime.utc_now()
      },
      schema: %{
        fields: [
          %{name: "coherence", type: "rating", min: 1, max: 5},
          %{name: "grounded", type: "rating", min: 1, max: 5},
          %{name: "novel", type: "rating", min: 1, max: 5},
          %{name: "balanced", type: "rating", min: 1, max: 5}
        ]
      },
      existing_labels: [],
      assigned_at: DateTime.utc_now(),
      metadata: %{}
    }
  end

  @impl true
  def submit_label(_assignment_id, values) do
    # Validate that required fields are present
    required = ["coherence", "grounded", "novel", "balanced"]

    missing =
      Enum.filter(required, fn field ->
        not Map.has_key?(values, field) and not Map.has_key?(values, String.to_atom(field))
      end)

    case missing do
      [] ->
        :ok

      fields ->
        {:error, {:validation, Enum.map(fields, &{&1, "is required"}) |> Map.new()}}
    end
  end

  @impl true
  def get_queue_stats(_queue_id) do
    {:ok,
     %QueueStats{
       total_samples: 500,
       labeled: 47,
       remaining: 453,
       agreement_scores: %{
         coherence: 0.82,
         grounded: 0.78,
         novel: 0.65,
         balanced: 0.75
       },
       active_labelers: 3
     }}
  end

  # Legacy API implementation

  @impl true
  def store_label(label) do
    if valid_label?(label) do
      {:ok, label}
    else
      {:error, :invalid_label}
    end
  end

  @impl true
  def total_labels do
    47
  end

  @impl true
  def statistics do
    %{
      total_labels: 47,
      avg_coherence: 3.8,
      avg_grounded: 4.1,
      avg_novel: 3.2,
      avg_balanced: 3.9,
      total_sessions: 5,
      avg_time_per_label_ms: 45_000
    }
  end

  @impl true
  def export_csv do
    {:ok, "sample_id,coherence,grounded,novel,balanced,notes\n"}
  end

  @doc """
  Get all labels for a specific session (legacy API).
  """
  def session_labels(_session_id) do
    []
  end

  # Private helpers

  defp valid_label?(label) do
    required_keys = [:sample_id, :session_id, :user_id, :ratings, :labeled_at]
    Enum.all?(required_keys, &Map.has_key?(label, &1))
  end
end
