defmodule Ingot.AnvilClient do
  @moduledoc """
  Facade for interacting with Anvil's `/v1` IR API.

  Delegates to a configurable adapter (mock/elixir/http) so tests and
  deployments can swap implementations without touching callers.
  """

  alias LabelingIR.{Assignment, Label}

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

  @callback get_next_assignment(queue_id, user_id, opts :: Keyword.t()) ::
              {:ok, Assignment.t()} | {:error, error()}

  @callback submit_label(assignment_id, Label.t() | map(), opts :: Keyword.t()) ::
              {:ok, Label.t()} | {:error, error()}

  @callback get_queue_stats(queue_id, opts :: Keyword.t()) :: {:ok, map()} | {:error, error()}

  @callback check_queue_access(user_id, queue_id, opts :: Keyword.t()) ::
              {:ok, boolean()} | {:error, error()}

  @callback health_check() :: {:ok, :healthy} | {:error, error()}

  @optional_callbacks check_queue_access: 3, health_check: 0

  def get_next_assignment(queue_id, user_id, opts \\ []),
    do: dispatch(:get_next_assignment, [queue_id, user_id, opts])

  def submit_label(assignment_id, label, opts \\ []),
    do: dispatch(:submit_label, [assignment_id, label, opts])

  def get_queue_stats(queue_id, opts \\ []), do: dispatch(:get_queue_stats, [queue_id, opts])

  def check_queue_access(user_id, queue_id, opts \\ []) do
    mod = adapter()
    Code.ensure_loaded(mod)

    if function_exported?(mod, :check_queue_access, 3) do
      mod.check_queue_access(user_id, queue_id, opts)
    else
      {:ok, true}
    end
  end

  def health_check do
    mod = adapter()
    Code.ensure_loaded(mod)

    if function_exported?(mod, :health_check, 0) do
      mod.health_check()
    else
      {:ok, :healthy}
    end
  end

  defp dispatch(fun, args) do
    mod = adapter()
    Code.ensure_loaded(mod)
    arity = length(args)

    cond do
      function_exported?(mod, fun, arity) ->
        apply(mod, fun, args)

      function_exported?(mod, fun, arity - 1) ->
        apply(mod, fun, Enum.drop(args, -1))

      true ->
        {:error, :not_available}
    end
  end

  defp adapter do
    Application.get_env(:ingot, :anvil_client_adapter, Ingot.AnvilClient.MockAdapter)
  end
end
