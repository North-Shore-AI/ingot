defmodule Ingot.ForgeClient.HTTPAdapter do
  @moduledoc """
  HTTP adapter for Forge `/v1` IR API.

  Configuration:
    * `:ingot, :forge_base_url` (default: http://localhost:4102)
    * `:ingot, :default_tenant_id` (optional) for read scoping
  """

  @behaviour Ingot.ForgeClient

  alias LabelingIR.Sample

  @impl true
  def get_sample(sample_id, opts \\ []) do
    url = "#{base_url()}/v1/samples/#{sample_id}"

    case request(:get, url, opts) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, decode_sample(Jason.decode!(body))}

      {:ok, %{status_code: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, {:unexpected, reason}}
    end
  end

  @impl true
  def queue_stats(_opts \\ []) do
    # Forge API does not yet expose queue stats; return neutral values.
    {:ok, %{total: 0, remaining: 0, labeled: 0}}
  end

  @impl true
  def health_check do
    case request(:get, "#{base_url()}/health", []) do
      {:ok, %{status_code: code}} when code in 200..499 -> {:ok, :healthy}
      {:error, reason} -> {:error, reason}
    end
  end

  ## Helpers

  defp request(method, url, opts) do
    headers = [{"content-type", "application/json"}] ++ tenant_header(opts)
    http_opts = [recv_timeout: 5_000]

    case method do
      :get ->
        if Code.ensure_loaded?(HTTPoison) do
          HTTPoison.get(url, headers, http_opts)
        else
          {:error, :httpoison_not_available}
        end
    end
  end

  defp tenant_header(opts) do
    tenant =
      Keyword.get(opts, :tenant_id) ||
        Application.get_env(:ingot, :default_tenant_id)

    case tenant do
      nil -> []
      tenant -> [{"x-tenant-id", tenant}]
    end
  end

  defp base_url do
    Application.get_env(:ingot, :forge_base_url, "http://localhost:4102")
  end

  defp decode_sample(map) do
    %Sample{
      id: map["id"],
      tenant_id: map["tenant_id"],
      namespace: Map.get(map, "namespace"),
      pipeline_id: map["pipeline_id"],
      payload: Map.get(map, "payload", %{}),
      artifacts: Map.get(map, "artifacts", []),
      metadata: Map.get(map, "metadata", %{}),
      lineage_ref: Map.get(map, "lineage_ref"),
      created_at: parse_datetime(map["created_at"])
    }
  end

  defp parse_datetime(nil), do: DateTime.utc_now()

  defp parse_datetime(val) when is_binary(val) do
    case DateTime.from_iso8601(val) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
end
