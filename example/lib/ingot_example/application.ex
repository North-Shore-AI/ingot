defmodule IngotExample.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Telemetry supervisor
      IngotExampleWeb.Telemetry,
      # Start the endpoint
      IngotExampleWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: IngotExample.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    IngotExampleWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
