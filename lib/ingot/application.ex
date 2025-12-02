defmodule Ingot.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      IngotWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:ingot, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Ingot.PubSub},
      # Start ComponentRegistry for pluggable components
      {Ingot.Components.ComponentRegistry, []},
      # Start a worker by calling: Ingot.Worker.start_link(arg)
      # {Ingot.Worker, arg},
      # Start to serve requests, typically the last entry
      IngotWeb.Endpoint
    ]

    # Attach telemetry handler for Ingot, Forge, and Anvil events
    Ingot.TelemetryHandler.attach()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Ingot.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    IngotWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
