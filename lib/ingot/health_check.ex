defmodule Ingot.HealthCheck do
  @moduledoc """
  Health check module for Ingot.

  Checks the health of:
  - The Phoenix endpoint (is the server running?)
  - Forge service (can we reach it?)
  - Anvil service (can we reach it?)

  Used by the /health endpoint for monitoring and alerting.
  """

  alias Ingot.{ForgeClient, AnvilClient}

  @type health_status :: :healthy | :unhealthy

  @doc """
  Get overall health status.

  Returns :healthy if all services are reachable, :unhealthy otherwise.
  """
  @spec status() :: health_status()
  def status do
    checks = [
      check_endpoint(),
      check_forge(),
      check_anvil()
    ]

    if Enum.all?(checks, &(&1 == :ok)), do: :healthy, else: :unhealthy
  end

  @doc """
  Get detailed health status with per-service breakdowns.

  Returns a map with overall status, individual service statuses, and timestamp.
  """
  @spec detailed_status() :: map()
  def detailed_status do
    endpoint_status = check_endpoint()
    forge_status = check_forge()
    anvil_status = check_anvil()

    overall_status =
      if Enum.all?([endpoint_status, forge_status, anvil_status], &(&1 == :ok)) do
        :healthy
      else
        :unhealthy
      end

    %{
      status: overall_status,
      services: %{
        endpoint: endpoint_status,
        forge: forge_status,
        anvil: anvil_status
      },
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Check if the Phoenix endpoint is running.

  Returns :ok if the endpoint is running, :error otherwise.
  """
  @spec check_endpoint() :: :ok | :error
  def check_endpoint do
    # Check if the endpoint is running by verifying the supervisor is alive
    case Process.whereis(IngotWeb.Endpoint) do
      pid when is_pid(pid) -> :ok
      nil -> :error
    end
  end

  @doc """
  Check if Forge service is reachable.

  Returns :ok if Forge responds to health check, :error otherwise.
  """
  @spec check_forge() :: :ok | :error
  def check_forge do
    case ForgeClient.health_check() do
      {:ok, :healthy} -> :ok
      {:error, _reason} -> :error
    end
  rescue
    _ -> :error
  end

  @doc """
  Check if Anvil service is reachable.

  Returns :ok if Anvil responds to health check, :error otherwise.
  """
  @spec check_anvil() :: :ok | :error
  def check_anvil do
    case AnvilClient.health_check() do
      {:ok, :healthy} -> :ok
      {:error, _reason} -> :error
    end
  rescue
    _ -> :error
  end
end
