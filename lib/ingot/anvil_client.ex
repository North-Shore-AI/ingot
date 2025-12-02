defmodule Ingot.AnvilClient do
  @moduledoc """
  Behaviour for labeling operations via Anvil.

  Handles queue subscriptions, assignment fetching, label submission, and stats.
  Supports pluggable adapters for different deployment scenarios:
  - MockAdapter: For testing without running Anvil
  - ElixirAdapter: Direct in-process calls when deployed together
  - HTTPAdapter: REST API calls for separate deployments (future)
  """

  alias Ingot.DTO.{Assignment, QueueStats}

  @type queue_id :: String.t()
  @type assignment_id :: String.t()
  @type user_id :: String.t()
  @type error ::
          :not_found
          | :no_assignments
          | :timeout
          | :not_available
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
  @callback store_label(label :: map()) ::
              {:ok, map()} | {:error, :invalid_label | error()}

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
  @callback export_csv() :: {:ok, String.t()} | {:error, error()}

  # Auth API callbacks

  @doc """
  Upsert a user (create or update).

  Creates a new user or updates an existing one based on external_id.
  Used for OIDC just-in-time provisioning.
  """
  @callback upsert_user(attrs :: map()) ::
              {:ok, map()} | {:error, :invalid_attributes | error()}

  @doc """
  Get user roles.

  Returns a list of roles assigned to the user.
  """
  @callback get_user_roles(user_id) :: {:ok, [map()]} | {:error, error()}

  @doc """
  Check if user has access to a queue.

  Returns true if the user has permission to access the queue.
  """
  @callback check_queue_access(user_id, queue_id) :: {:ok, boolean()} | {:error, error()}

  @doc """
  Create an invite code for a queue.

  Generates an invite code that can be redeemed by external labelers.
  """
  @callback create_invite(attrs :: map()) :: {:ok, map()} | {:error, error()}

  @doc """
  Get invite by code.

  Returns invite details if the code is valid and not expired/exhausted.
  """
  @callback get_invite(code :: String.t()) ::
              {:ok, map()} | {:error, :not_found | :expired | :exhausted}

  @doc """
  Redeem an invite code.

  Creates a user and grants access to the queue associated with the invite.
  """
  @callback redeem_invite(code :: String.t(), user_attrs :: map()) ::
              {:ok, map()} | {:error, :not_found | :expired | :exhausted | error()}

  @doc """
  Health check for Anvil service.

  Returns :ok if Anvil is reachable and healthy, otherwise returns an error.
  """
  @callback health_check() :: {:ok, :healthy} | {:error, error()}

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

  # Auth API delegation

  @doc """
  Upsert a user (create or update).

  ## Examples

      iex> AnvilClient.upsert_user(%{external_id: "oidc_123", email: "user@example.com", name: "User"})
      {:ok, %{id: "user_123", external_id: "oidc_123", ...}}
  """
  def upsert_user(attrs), do: adapter().upsert_user(attrs)

  @doc """
  Get user roles.

  ## Examples

      iex> AnvilClient.get_user_roles("user_123")
      {:ok, [%{role: :labeler, scope: "queue:abc"}, ...]}
  """
  def get_user_roles(user_id), do: adapter().get_user_roles(user_id)

  @doc """
  Check if user has access to a queue.

  ## Examples

      iex> AnvilClient.check_queue_access("user_123", "queue_abc")
      {:ok, true}
  """
  def check_queue_access(user_id, queue_id), do: adapter().check_queue_access(user_id, queue_id)

  @doc """
  Create an invite code for a queue.

  ## Examples

      iex> AnvilClient.create_invite(%{queue_id: "queue_abc", role: :labeler, max_uses: 10})
      {:ok, %{code: "ABCD1234WXYZ", queue_id: "queue_abc", ...}}
  """
  def create_invite(attrs), do: adapter().create_invite(attrs)

  @doc """
  Get invite by code.

  ## Examples

      iex> AnvilClient.get_invite("ABCD1234WXYZ")
      {:ok, %{code: "ABCD1234WXYZ", queue_id: "queue_abc", ...}}
  """
  def get_invite(code), do: adapter().get_invite(code)

  @doc """
  Redeem an invite code.

  ## Examples

      iex> AnvilClient.redeem_invite("ABCD1234WXYZ", %{email: "labeler@example.com", name: "Labeler"})
      {:ok, %{user: %{id: "user_123", ...}, queue_id: "queue_abc", role: :labeler}}
  """
  def redeem_invite(code, user_attrs), do: adapter().redeem_invite(code, user_attrs)

  @doc """
  Health check for Anvil service.

  ## Examples

      iex> AnvilClient.health_check()
      {:ok, :healthy}

      iex> AnvilClient.health_check()
      {:error, :not_available}
  """
  def health_check, do: adapter().health_check()

  # Private helpers

  defp adapter do
    Application.get_env(:ingot, :anvil_client_adapter, Ingot.AnvilClient.MockAdapter)
  end
end
