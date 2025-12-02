defmodule IngotWeb.HealthController do
  use IngotWeb, :controller

  @moduledoc """
  Health check endpoint for monitoring and alerting.

  Returns JSON with overall status and individual service health checks.
  """

  alias Ingot.HealthCheck

  @doc """
  GET /health

  Returns 200 OK with health status when all services are healthy.
  Returns 503 Service Unavailable when any service is unhealthy.
  """
  def index(conn, _params) do
    health = HealthCheck.detailed_status()

    status_code = if health.status == :healthy, do: 200, else: 503

    response = %{
      status: to_string(health.status),
      services: %{
        endpoint: to_string(health.services.endpoint),
        forge: to_string(health.services.forge),
        anvil: to_string(health.services.anvil)
      },
      timestamp: DateTime.to_iso8601(health.timestamp)
    }

    conn
    |> put_status(status_code)
    |> json(response)
  end
end
