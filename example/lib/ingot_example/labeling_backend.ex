defmodule IngotExample.LabelingBackend do
  @moduledoc """
  Example backend implementation using in-memory mock data.

  This demonstrates how a host application would implement the
  `Ingot.Labeling.Backend` behaviour with their own data source.
  """

  @behaviour Ingot.Labeling.Backend

  alias LabelingIR.{Assignment, Sample, Schema, Label}

  @impl true
  def get_next_assignment(queue_id, user_id, _opts) do
    # Mock assignment for demonstration
    assignment = %Assignment{
      id: "asn-#{System.unique_integer([:positive])}",
      queue_id: queue_id,
      sample: mock_sample(),
      schema: mock_schema(),
      user_id: user_id,
      namespace: "example",
      lineage_ref: "example-lineage",
      metadata: %{},
      created_at: DateTime.utc_now()
    }

    {:ok, assignment}
  end

  @impl true
  def submit_label(assignment_id, label, _opts) do
    # In a real implementation, this would persist to a database
    # For now, just return success
    label_with_id =
      case label do
        %Label{} = l ->
          l

        map when is_map(map) ->
          struct!(Label, map)
      end

    IO.puts("✓ Label submitted for assignment #{assignment_id}")
    IO.inspect(label_with_id, label: "Label Data")

    {:ok, label_with_id}
  end

  @impl true
  def get_queue_stats(queue_id, _opts) do
    # Mock statistics
    stats = %{
      queue_id: queue_id,
      remaining: 42,
      labeled: 158,
      total: 200,
      completion_rate: 0.79
    }

    {:ok, stats}
  end

  @impl true
  def check_queue_access(_user_id, _queue_id, _opts) do
    # Allow all access in example app
    {:ok, true}
  end

  ## Private Helpers

  defp mock_sample do
    %Sample{
      id: "smp-#{System.unique_integer([:positive])}",
      payload: %{
        "text" => "This is an example text sample for labeling.",
        "metadata" => %{
          "source" => "example-dataset",
          "category" => "demonstration"
        }
      },
      namespace: "example",
      artifacts: [],
      metadata: %{},
      created_at: DateTime.utc_now()
    }
  end

  defp mock_schema do
    %Schema{
      id: "schema-example",
      namespace: "example",
      fields: [
        %{
          name: "quality",
          type: "scale",
          min: 1,
          max: 5,
          default: 3,
          required: true,
          help: "Rate the overall quality"
        },
        %{
          name: "clarity",
          type: "scale",
          min: 1,
          max: 5,
          default: 3,
          required: true,
          help: "Rate the clarity"
        },
        %{
          name: "notes",
          type: "text",
          required: false,
          help: "Additional notes"
        }
      ],
      metadata: %{},
      created_at: DateTime.utc_now()
    }
  end
end
