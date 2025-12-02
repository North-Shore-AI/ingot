defmodule Ingot.ForgeClient.ElixirAdapter do
  @moduledoc """
  Elixir adapter for ForgeClient - direct in-process integration.

  This adapter makes direct function calls to the Forge application when
  Ingot and Forge are deployed together in the same Erlang VM.

  When Forge is fully integrated, this adapter will:
  - Call Forge.Storage.Postgres or equivalent modules
  - Translate Forge domain structs to Ingot DTOs
  - Handle errors and normalize them to standard client errors
  - Apply timeouts and retries for resilience
  """

  @behaviour Ingot.ForgeClient

  alias Ingot.DTO.{Sample, Artifact}

  @impl true
  def get_sample(sample_id) do
    # TODO: Integrate with Forge.Storage when available
    # case Forge.Storage.Postgres.fetch(sample_id, %{}) do
    #   {:ok, sample, _state} -> {:ok, to_sample_dto(sample)}
    #   {:error, :not_found} -> {:error, :not_found}
    #   {:error, reason} -> {:error, normalize_error(reason)}
    # end
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :forge_error}}
  end

  @impl true
  def get_artifacts(sample_id) do
    # TODO: Integrate with Forge.Artifacts when available
    # case Forge.Artifacts.list_for_sample(sample_id) do
    #   {:ok, artifacts} -> {:ok, Enum.map(artifacts, &to_artifact_dto/1)}
    #   {:error, reason} -> {:error, normalize_error(reason)}
    # end
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :forge_error}}
  end

  @impl true
  def queue_stats do
    # TODO: Integrate with Forge.Queue when available
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :forge_error}}
  end

  @impl true
  def fetch_next_sample(user_id) do
    # TODO: Integrate with Forge when available
    {:error, :not_available}
  rescue
    UndefinedFunctionError -> {:error, :not_available}
    _ -> {:error, {:unexpected, :forge_error}}
  end

  @impl true
  def skip_sample(_sample_id, _user_id) do
    # TODO: Integrate with Forge when available
    :ok
  end

  def generate_batch(_count) do
    # TODO: Integrate with Forge when available
    {:error, :not_available}
  end

  # Private helpers for DTO translation (to be implemented when integrating)

  # defp to_sample_dto(%Forge.Sample{} = sample) do
  #   %Sample{
  #     id: sample.id,
  #     pipeline_id: to_string(sample.pipeline),
  #     payload: sample.data,
  #     artifacts: [],
  #     metadata: sample.measurements || %{},
  #     created_at: sample.created_at
  #   }
  # end

  # defp to_artifact_dto(%Forge.Artifact{} = artifact) do
  #   %Artifact{
  #     id: artifact.id,
  #     sample_id: artifact.sample_id,
  #     artifact_type: artifact.artifact_type,
  #     url: Forge.Storage.signed_url(artifact.storage_key),
  #     filename: artifact.filename,
  #     size_bytes: artifact.size_bytes,
  #     content_type: artifact.content_type
  #   }
  # end

  # defp normalize_error(:not_found), do: :not_found
  # defp normalize_error({:timeout, _}), do: :timeout
  # defp normalize_error(reason), do: {:unexpected, reason}
end
