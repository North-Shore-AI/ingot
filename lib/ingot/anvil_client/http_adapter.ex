defmodule Ingot.AnvilClient.HTTPAdapter do
  @moduledoc """
  HTTP adapter for Anvil `/v1` IR API.

  Configuration:
    * `:ingot, :anvil_base_url` (default: http://localhost:4101)
    * `:ingot, :default_tenant_id` (optional) for write headers
  """

  @behaviour Ingot.AnvilClient

  alias LabelingIR.{Assignment, Label, Sample, Schema}

  @impl true
  def get_next_assignment(queue_id, user_id, opts \\ []) do
    url = "#{base_url()}/v1/queues/#{queue_id}/assignments/next?user_id=#{URI.encode(user_id)}"

    with {:ok, %{status_code: 200, body: body}} <- request(:get, url, nil, opts),
         {:ok, decoded} <- Jason.decode(body),
         {:ok, assignment} <- decode_assignment(decoded) do
      {:ok, assignment}
    else
      {:ok, %{status_code: 404}} -> {:error, :no_assignments}
      {:error, reason} -> {:error, {:unexpected, reason}}
    end
  end

  @impl true
  def submit_label(_assignment_id, %Label{} = label, opts \\ []) do
    payload = Map.from_struct(label)
    url = "#{base_url()}/v1/labels"

    case request(:post, url, Jason.encode!(payload), opts ++ [tenant_id: label.tenant_id]) do
      {:ok, %{status_code: code, body: body}} when code in 200..299 ->
        {:ok, Map.merge(payload, Jason.decode!(body)) |> struct(Label)}

      {:ok, %{status_code: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, {:unexpected, reason}}
    end
  end

  @impl true
  def get_queue_stats(queue_id, opts \\ []) do
    url = "#{base_url()}/v1/queues/#{queue_id}"

    case request(:get, url, nil, opts) do
      {:ok, %{status_code: 200, body: body}} ->
        decoded = Jason.decode!(body)
        stats = Map.get(decoded, "stats", %{}) || %{}
        {:ok, Map.merge(%{remaining: 0, labeled: 0}, stats)}

      {:ok, %{status_code: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, {:unexpected, reason}}
    end
  end

  @impl true
  def check_queue_access(_user_id, queue_id, opts \\ []) do
    case request(:get, "#{base_url()}/v1/queues/#{queue_id}", nil, opts) do
      {:ok, %{status_code: 200}} -> {:ok, true}
      {:ok, %{status_code: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, {:unexpected, reason}}
    end
  end

  @impl true
  def health_check do
    case request(:get, "#{base_url()}/health", nil, []) do
      {:ok, %{status_code: code}} when code in 200..499 -> {:ok, :healthy}
      {:error, reason} -> {:error, reason}
    end
  end

  ## Helpers

  defp request(method, url, body, opts) do
    headers = [{"content-type", "application/json"}] ++ tenant_header(opts)
    http_opts = [recv_timeout: 5_000]

    if Code.ensure_loaded?(HTTPoison) do
      case method do
        :get -> HTTPoison.get(url, headers, http_opts)
        :post -> HTTPoison.post(url, body || "{}", headers, http_opts)
      end
    else
      {:error, :httpoison_not_available}
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
    Application.get_env(:ingot, :anvil_base_url, "http://localhost:4101")
  end

  defp decode_assignment(map) do
    with {:ok, sample} <- decode_sample(map["sample"]),
         {:ok, schema} <- decode_schema(map["schema"]) do
      {:ok,
       %Assignment{
         id: map["id"],
         queue_id: map["queue_id"],
         tenant_id: map["tenant_id"],
         namespace: Map.get(map, "namespace"),
         sample: sample,
         schema: schema,
         existing_labels: [],
         expires_at: nil,
         lineage_ref: Map.get(map, "lineage_ref"),
         metadata: Map.get(map, "metadata", %{})
       }}
    else
      _ -> {:error, :invalid_payload}
    end
  end

  defp decode_sample(map) when is_map(map) do
    {:ok,
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
     }}
  end

  defp decode_sample(_), do: {:error, :invalid_payload}

  defp decode_schema(map) when is_map(map) do
    fields =
      Map.get(map, "fields", [])
      |> Enum.map(fn field ->
        %Schema.Field{
          name: field["name"],
          type: normalize_type(field["type"]),
          required: field["required"] || false,
          min: field["min"],
          max: field["max"],
          default: field["default"],
          options: field["options"],
          help: field["help"]
        }
      end)

    {:ok,
     %Schema{
       id: map["id"],
       tenant_id: map["tenant_id"],
       namespace: Map.get(map, "namespace"),
       fields: fields,
       layout: Map.get(map, "layout"),
       component_module: Map.get(map, "component_module"),
       metadata: Map.get(map, "metadata", %{})
     }}
  end

  defp decode_schema(_), do: {:error, :invalid_payload}

  defp parse_datetime(nil), do: DateTime.utc_now()

  defp parse_datetime(val) when is_binary(val) do
    case DateTime.from_iso8601(val) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt

  defp normalize_type(type) when is_atom(type), do: type

  defp normalize_type(type) when is_binary(type) do
    try do
      String.to_existing_atom(type)
    rescue
      ArgumentError -> String.to_atom(type)
    end
  end

  defp normalize_type(type), do: type
end
