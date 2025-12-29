defmodule Ingot.AnvilClient.MockAdapter do
  @moduledoc """
  Mock adapter for AnvilClient returning LabelingIR structs for tests/dev.
  """

  @behaviour Ingot.AnvilClient

  alias LabelingIR.{Assignment, Label, Sample, Schema}

  @impl true
  def get_next_assignment(queue_id, user_id, opts) do
    get_next_assignment_impl(queue_id, user_id, opts)
  end

  defp get_next_assignment_impl(queue_id, _user_id, _opts) do
    schema = %Schema{
      id: "schema-mock",
      tenant_id: "tenant_mock",
      fields: [%Schema.Field{name: "quality", type: :scale, min: 1, max: 5, required: true}],
      metadata: %{}
    }

    sample = %Sample{
      id: "sample-#{:rand.uniform(1000)}",
      tenant_id: "tenant_mock",
      pipeline_id: "test_pipeline",
      payload: %{"headline" => "Mock headline"},
      artifacts: [],
      metadata: %{source: "mock"},
      created_at: DateTime.utc_now()
    }

    assignment = %Assignment{
      id: "asst-#{:rand.uniform(1000)}",
      queue_id: queue_id,
      tenant_id: "tenant_mock",
      sample: sample,
      schema: schema,
      existing_labels: [],
      metadata: %{"component_module" => "Ingot.Components.DefaultComponent"}
    }

    {:ok, assignment}
  end

  @impl true
  def submit_label(assignment_id, payload, opts) do
    submit_label_impl(assignment_id, payload, opts)
  end

  defp submit_label_impl(_assignment_id, %Label{} = label, _opts), do: {:ok, label}

  defp submit_label_impl(_assignment_id, params, _opts) do
    label =
      %Label{
        id: params[:id] || params["id"] || "lbl-#{:rand.uniform(10_000)}",
        assignment_id: params[:assignment_id] || params["assignment_id"],
        sample_id: params[:sample_id] || params["sample_id"],
        queue_id: params[:queue_id] || params["queue_id"],
        tenant_id: params[:tenant_id] || params["tenant_id"] || "tenant_mock",
        user_id: params[:user_id] || params["user_id"] || "user-mock",
        values: params[:values] || params["values"] || %{},
        time_spent_ms: params[:time_spent_ms] || params["time_spent_ms"] || 0,
        created_at: params[:created_at] || params["created_at"] || DateTime.utc_now(),
        lineage_ref: params[:lineage_ref] || params["lineage_ref"],
        metadata: params[:metadata] || params["metadata"] || %{}
      }

    {:ok, label}
  end

  @impl true
  def get_queue_stats(queue_id, opts) do
    get_queue_stats_impl(queue_id, opts)
  end

  defp get_queue_stats_impl(_queue_id, _opts) do
    {:ok, %{remaining: 1, labeled: 0}}
  end

  @impl true
  def check_queue_access(user_id, queue_id, opts) do
    check_queue_access_impl(user_id, queue_id, opts)
  end

  defp check_queue_access_impl(_user_id, _queue_id, _opts), do: {:ok, true}

  @impl true
  def health_check, do: {:ok, :healthy}
end
