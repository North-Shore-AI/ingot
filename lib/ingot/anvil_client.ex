defmodule Ingot.AnvilClient do
  @moduledoc """
  Behaviour for labeling operations via Anvil.

  Handles queue subscriptions, assignment fetching, label submission, and stats.
  Supports pluggable adapters for different deployment scenarios:
  - MockAdapter: For testing without running Anvil
  - ElixirAdapter: Direct in-process calls when deployed together
  - HTTPAdapter: REST API calls for separate deployments (future)
  """

  alias Ingot.DTO.{Assignment, Label, QueueStats}

  @type queue_id :: String.t()
  @type assignment_id :: String.t()
  @type user_id :: String.t()
  @type error ::
          :not_found
          | :no_assignments
          | :timeout
          | {:validation, map()}
          | {:unexpected, term()}

  @doc """
  Get next assignment from a queue for a user.

  Returns an assignment with the sample pre-fetched and any existing
  labels for review/adjudication scenarios.
  """
  @callback get_next_assignment(queue_id, user_id) ::
              {:ok, Assignment.t()} | {:error, error()}

  @doc """
  Submit a completed label.

  Values should conform to the schema defined in the assignment.
  """
  @callback submit_label(assignment_id, values :: map()) :: :ok | {:error, error()}

  @doc """
  Get queue-level statistics.

  Returns aggregate progress and agreement metrics.
  """
  @callback get_queue_stats(queue_id) :: {:ok, QueueStats.t()} | {:error, error()}

  # Legacy API support (for backward compatibility with existing code)
  @doc """
  Store a completed label.

  Legacy API - maintained for backward compatibility.
  """
  @callback store_label(label :: map()) :: {:ok, map()} | {:error, :invalid_label}

  @doc """
  Get total count of all labels.

  Legacy API - maintained for backward compatibility.
  """
  @callback total_labels() :: integer()

  @doc """
  Get labeling statistics.

  Legacy API - maintained for backward compatibility.
  """
  @callback statistics() :: map()

  @doc """
  Export all labels as CSV.

  Legacy API - maintained for backward compatibility.
  """
  @callback export_csv() :: {:ok, String.t()}

  # Public API - delegates to configured adapter

  @doc """
  Get next assignment from a queue for a user.

  ## Examples

      iex> AnvilClient.get_next_assignment("queue-1", "user-123")
      {:ok, %Ingot.DTO.Assignment{...}}

      iex> AnvilClient.get_next_assignment("empty-queue", "user-123")
      {:error, :no_assignments}
  """
  def get_next_assignment(queue_id, user_id),
    do: adapter().get_next_assignment(queue_id, user_id)

  @doc """
  Submit a completed label.

  ## Examples

      iex> AnvilClient.submit_label("assignment-1", %{coherence: 4})
      :ok

      iex> AnvilClient.submit_label("assignment-1", %{invalid: "data"})
      {:error, {:validation, %{coherence: "is required"}}}
  """
  def submit_label(assignment_id, values), do: adapter().submit_label(assignment_id, values)

  @doc """
  Get queue-level statistics.

  ## Examples

      iex> AnvilClient.get_queue_stats("queue-1")
      {:ok, %Ingot.DTO.QueueStats{total_samples: 100, labeled: 47, ...}}
  """
  def get_queue_stats(queue_id), do: adapter().get_queue_stats(queue_id)

  # Legacy API delegation

  @doc """
  Store a completed label.

  ## Examples

      iex> label = %{sample_id: "s1", ratings: %{coherence: 4}}
      iex> AnvilClient.store_label(label)
      {:ok, label}
  """
  def store_label(label), do: adapter().store_label(label)

  @doc """
  Get total count of all labels.

  ## Examples

      iex> AnvilClient.total_labels()
      47
  """
  def total_labels, do: adapter().total_labels()

  @doc """
  Get labeling statistics.

  ## Examples

      iex> AnvilClient.statistics()
      %{total_labels: 47, avg_coherence: 3.8, ...}
  """
  def statistics, do: adapter().statistics()

  @doc """
  Export all labels as CSV.

  ## Examples

      iex> AnvilClient.export_csv()
      {:ok, "sample_id,coherence\\n..."}
  """
  def export_csv, do: adapter().export_csv()

  @doc """
  Get all labels for a specific session.

  Legacy API - maintained for backward compatibility.
  """
  def session_labels(session_id), do: adapter().session_labels(session_id)

  # Private helpers

  defp adapter do
    Application.get_env(:ingot, :anvil_client_adapter, Ingot.AnvilClient.MockAdapter)
  end
end
