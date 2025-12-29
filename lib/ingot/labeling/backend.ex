defmodule Ingot.Labeling.Backend do
  @moduledoc """
  Behaviour for labeling data operations.

  This behaviour allows host applications to provide their own backend
  implementation for fetching assignments, submitting labels, and retrieving
  queue statistics. The host app can use any data source (Ecto, HTTP API,
  in-memory store, etc.) as long as it implements these callbacks.

  ## Example Implementation

      defmodule MyApp.LabelingBackend do
        @behaviour Ingot.Labeling.Backend
        alias MyApp.Repo
        alias MyApp.Labeling

        @impl true
        def get_next_assignment(queue_id, user_id, opts) do
          tenant_id = Keyword.get(opts, :tenant_id, "default")

          case Labeling.fetch_next_assignment(queue_id, user_id, tenant_id) do
            nil -> {:error, :no_assignments}
            assignment -> {:ok, assignment}
          end
        end

        @impl true
        def submit_label(assignment_id, label_data, opts) do
          tenant_id = Keyword.get(opts, :tenant_id, "default")

          Labeling.create_label(assignment_id, label_data, tenant_id)
        end

        @impl true
        def get_queue_stats(queue_id, opts) do
          tenant_id = Keyword.get(opts, :tenant_id, "default")

          stats = Labeling.queue_stats(queue_id, tenant_id)
          {:ok, stats}
        end
      end

  ## Usage in Router

      labeling_routes "/labeling",
        config: %{backend: MyApp.LabelingBackend}
  """

  alias LabelingIR.{Assignment, Label}

  @type queue_id :: String.t()
  @type assignment_id :: String.t()
  @type user_id :: String.t()
  @type tenant_id :: String.t()
  @type error ::
          :not_found
          | :no_assignments
          | :timeout
          | :not_available
          | {:validation, map()}
          | {:unexpected, term()}

  @doc """
  Get the next assignment for a user from a queue.

  ## Parameters

  - `queue_id` - The queue identifier
  - `user_id` - The user identifier
  - `opts` - Keyword list of options (e.g., `tenant_id: "production"`)

  ## Returns

  - `{:ok, assignment}` - Returns the next assignment
  - `{:error, :no_assignments}` - No assignments available
  - `{:error, reason}` - Other error
  """
  @callback get_next_assignment(queue_id, user_id, opts :: Keyword.t()) ::
              {:ok, Assignment.t()} | {:error, error()}

  @doc """
  Submit a label for an assignment.

  ## Parameters

  - `assignment_id` - The assignment identifier
  - `label` - The label struct or label data map
  - `opts` - Keyword list of options (e.g., `tenant_id: "production"`)

  ## Returns

  - `{:ok, label}` - Returns the stored label
  - `{:error, reason}` - Validation or storage error
  """
  @callback submit_label(assignment_id, Label.t() | map(), opts :: Keyword.t()) ::
              {:ok, Label.t()} | {:error, error()}

  @doc """
  Get statistics for a queue.

  ## Parameters

  - `queue_id` - The queue identifier
  - `opts` - Keyword list of options (e.g., `tenant_id: "production"`)

  ## Returns

  - `{:ok, stats}` - Returns a map with statistics (e.g., %{remaining: 10, labeled: 90})
  - `{:error, reason}` - Error retrieving stats
  """
  @callback get_queue_stats(queue_id, opts :: Keyword.t()) :: {:ok, map()} | {:error, error()}

  @doc """
  Optional: Check if a user has access to a queue.

  ## Parameters

  - `user_id` - The user identifier
  - `queue_id` - The queue identifier
  - `opts` - Keyword list of options

  ## Returns

  - `{:ok, true}` - User has access
  - `{:ok, false}` - User does not have access
  - `{:error, reason}` - Error checking access
  """
  @callback check_queue_access(user_id, queue_id, opts :: Keyword.t()) ::
              {:ok, boolean()} | {:error, error()}

  @optional_callbacks check_queue_access: 3
end
