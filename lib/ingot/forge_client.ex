defmodule Ingot.ForgeClient do
  @moduledoc """
  Facade for Forge `/v1` IR API.

  Uses a pluggable adapter so tests can run without a Forge service.
  """

  alias LabelingIR.Sample

  @type sample_id :: String.t()
  @type error :: :not_found | :timeout | :network | :not_available | {:unexpected, term()}

  @callback get_sample(sample_id, opts :: Keyword.t()) :: {:ok, Sample.t()} | {:error, error()}
  @callback queue_stats(opts :: Keyword.t()) :: {:ok, map()} | {:error, error()}
  @callback health_check() :: {:ok, :healthy} | {:error, error()}

  @optional_callbacks health_check: 0

  def get_sample(sample_id, opts \\ []), do: dispatch(:get_sample, [sample_id, opts])
  def queue_stats(opts \\ []), do: dispatch(:queue_stats, [opts])

  def health_check do
    if function_exported?(adapter(), :health_check, 0) do
      adapter().health_check()
    else
      {:ok, :healthy}
    end
  end

  defp dispatch(fun, args) do
    mod = adapter()
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
    Application.get_env(:ingot, :forge_client_adapter, Ingot.ForgeClient.MockAdapter)
  end
end
