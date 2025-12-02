defmodule Ingot.AnvilClient.ElixirAdapter do
  @moduledoc """
  Elixir adapter for AnvilClient - direct in-process integration.

  This adapter makes direct function calls to the Anvil application when
  Ingot and Anvil are deployed together in the same Erlang VM.

  When Anvil is fully integrated, this adapter will:
  - Call Anvil.Queue or equivalent modules
  - Translate Anvil domain structs to Ingot DTOs
  - Handle errors and normalize them to standard client errors
  - Apply timeouts and retries for resilience
  """

  @behaviour Ingot.AnvilClient

  @impl true
  def get_next_assignment(_queue_id, _user_id) do
    # TODO: Integrate with Anvil.Queue when available
    # case Anvil.Queue.get_next_assignment(queue_id, user_id) do
    #   {:ok, assignment} -> {:ok, to_assignment_dto(assignment)}
    #   {:error, :no_assignments} -> {:error, :no_assignments}
    #   {:error, reason} -> {:error, normalize_error(reason)}
    # end
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :anvil_error}}
  end

  @impl true
  def submit_label(_assignment_id, _values) do
    # TODO: Integrate with Anvil.Labels when available
    # case Anvil.Labels.submit(assignment_id, values) do
    #   :ok -> :ok
    #   {:error, %Ecto.Changeset{} = changeset} ->
    #     {:error, {:validation, errors_from_changeset(changeset)}}
    #   {:error, reason} -> {:error, normalize_error(reason)}
    # end
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :anvil_error}}
  end

  @impl true
  def get_queue_stats(_queue_id) do
    # TODO: Integrate with Anvil.Stats when available
    # case Anvil.Stats.get_queue_stats(queue_id) do
    #   {:ok, stats} -> {:ok, to_queue_stats_dto(stats)}
    #   {:error, reason} -> {:error, normalize_error(reason)}
    # end
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :anvil_error}}
  end

  @impl true
  def store_label(_label) do
    # TODO: Integrate with Anvil when available
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :anvil_error}}
  end

  @impl true
  def total_labels do
    # TODO: Integrate with Anvil when available
    0
  rescue
    UndefinedFunctionError -> 0
    _ -> 0
  end

  @impl true
  def statistics do
    # TODO: Integrate with Anvil when available
    %{}
  rescue
    UndefinedFunctionError -> %{}
    _ -> %{}
  end

  @impl true
  def export_csv do
    # TODO: Integrate with Anvil when available
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :anvil_error}}
  end

  def session_labels(_session_id) do
    # TODO: Integrate with Anvil when available
    []
  rescue
    UndefinedFunctionError -> []
    _ -> []
  end

  # Auth API implementation

  @impl true
  def upsert_user(_attrs) do
    # TODO: Integrate with Anvil when available
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :anvil_error}}
  end

  @impl true
  def get_user_roles(_user_id) do
    # TODO: Integrate with Anvil when available
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :anvil_error}}
  end

  @impl true
  def check_queue_access(_user_id, _queue_id) do
    # TODO: Integrate with Anvil when available
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :anvil_error}}
  end

  @impl true
  def create_invite(_attrs) do
    # TODO: Integrate with Anvil when available
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :anvil_error}}
  end

  @impl true
  def get_invite(_code) do
    # TODO: Integrate with Anvil when available
    {:error, :not_found}
  rescue
    UndefinedFunctionError -> {:error, :not_found}
    _ -> {:error, {:unexpected, :anvil_error}}
  end

  @impl true
  def redeem_invite(_code, _user_attrs) do
    # TODO: Integrate with Anvil when available
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :anvil_error}}
  end

  @impl true
  def health_check do
    # TODO: When Anvil is integrated, add a proper health check
    # For now, return :not_available since Anvil is not integrated
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :anvil_error}}
  end

  # Private helpers for DTO translation (to be implemented when integrating)

  # defp to_assignment_dto(%Anvil.Assignment{} = assignment) do
  #   %Assignment{
  #     id: assignment.id,
  #     queue_id: assignment.queue_id,
  #     sample: fetch_sample(assignment.sample_id),
  #     schema: assignment.label_schema,
  #     existing_labels: Enum.map(assignment.existing_labels, &to_label_dto/1),
  #     assigned_at: assignment.assigned_at,
  #     metadata: assignment.metadata || %{}
  #   }
  # end

  # defp to_queue_stats_dto(%Anvil.QueueStats{} = stats) do
  #   %QueueStats{
  #     total_samples: stats.total_samples,
  #     labeled: stats.labeled_count,
  #     remaining: stats.remaining_count,
  #     agreement_scores: stats.agreement_metrics,
  #     active_labelers: stats.active_labeler_count
  #   }
  # end

  # defp normalize_error(:not_found), do: :not_found
  # defp normalize_error(:timeout), do: :timeout
  # defp normalize_error(reason), do: {:unexpected, reason}

  # defp errors_from_changeset(changeset) do
  #   Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
  #     Enum.reduce(opts, msg, fn {key, value}, acc ->
  #       String.replace(acc, "%{#{key}}", to_string(value))
  #     end)
  #   end)
  # end
end
