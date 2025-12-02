defmodule Ingot.ForgeClient do
  @moduledoc """
  Behaviour for fetching samples and artifacts from Forge.

  Ingot uses read-only operations; no sample creation/mutation.
  Supports pluggable adapters for different deployment scenarios:
  - MockAdapter: For testing without running Forge
  - ElixirAdapter: Direct in-process calls when deployed together
  - HTTPAdapter: REST API calls for separate deployments (future)
  """

  alias Ingot.DTO.{Sample, Artifact}

  @type sample_id :: String.t()
  @type error :: :not_found | :timeout | :network | :not_available | {:unexpected, term()}

  @doc """
  Fetch a sample by ID.

  Returns the sample DTO with embedded artifacts and metadata.
  """
  @callback get_sample(sample_id) :: {:ok, Sample.t()} | {:error, error()}

  @doc """
  Fetch all artifacts for a sample.

  Artifacts are media files (images, audio, etc.) with signed URLs.
  """
  @callback get_artifacts(sample_id) :: {:ok, [Artifact.t()]} | {:error, error()}

  @doc """
  Get queue statistics.

  Returns aggregate statistics about sample queues.
  """
  @callback queue_stats() :: {:ok, map()} | {:error, error()}

  # Legacy API support (for backward compatibility with existing code)
  @doc """
  Fetch next sample from queue for the given user.

  Legacy API - maintained for backward compatibility.
  """
  @callback fetch_next_sample(user_id :: String.t()) ::
              {:ok, map()} | {:error, :queue_empty | error()}

  @doc """
  Mark sample as skipped by the user.

  Legacy API - maintained for backward compatibility.
  """
  @callback skip_sample(sample_id, user_id :: String.t()) :: :ok

  # Public API - delegates to configured adapter

  @doc """
  Fetch a sample by ID.

  ## Examples

      iex> ForgeClient.get_sample("sample-123")
      {:ok, %Ingot.DTO.Sample{id: "sample-123", ...}}

      iex> ForgeClient.get_sample("nonexistent")
      {:error, :not_found}
  """
  def get_sample(sample_id), do: adapter().get_sample(sample_id)

  @doc """
  Fetch all artifacts for a sample.

  ## Examples

      iex> ForgeClient.get_artifacts("sample-123")
      {:ok, [%Ingot.DTO.Artifact{...}]}
  """
  def get_artifacts(sample_id), do: adapter().get_artifacts(sample_id)

  @doc """
  Get queue statistics.

  ## Examples

      iex> ForgeClient.queue_stats()
      {:ok, %{total: 100, completed: 50, remaining: 50}}
  """
  def queue_stats, do: adapter().queue_stats()

  # Legacy API delegation

  @doc """
  Fetch next sample from queue for the given user.

  ## Examples

      iex> ForgeClient.fetch_next_sample("user-123")
      {:ok, %{id: "sample-1", narrative_a: "...", ...}}
  """
  def fetch_next_sample(user_id), do: adapter().fetch_next_sample(user_id)

  @doc """
  Mark sample as skipped by the user.

  ## Examples

      iex> ForgeClient.skip_sample("sample-1", "user-123")
      :ok
  """
  def skip_sample(sample_id, user_id), do: adapter().skip_sample(sample_id, user_id)

  @doc """
  Generate new batch of samples.

  Legacy API - maintained for backward compatibility.
  """
  def generate_batch(count), do: adapter().generate_batch(count)

  # Private helpers

  defp adapter do
    Application.get_env(:ingot, :forge_client_adapter, Ingot.ForgeClient.MockAdapter)
  end
end
