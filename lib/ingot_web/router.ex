defmodule IngotWeb.Router do
  use IngotWeb, :router
  import Ingot.Labeling.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {IngotWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Auth pipelines
  pipeline :require_auth do
    plug IngotWeb.Plugs.RequireAuth
  end

  pipeline :require_labeler do
    plug IngotWeb.Plugs.RequireAuth
    plug IngotWeb.Plugs.RequireRole, role: :labeler
  end

  pipeline :require_admin do
    plug IngotWeb.Plugs.RequireAuth
    plug IngotWeb.Plugs.RequireRole, role: :admin
  end

  scope "/", IngotWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Labeling routes using composable macro
  scope "/" do
    pipe_through :browser

    labeling_routes("/dashboard",
      root_layout: {IngotWeb.Layouts, :root},
      config: %{
        backend: Ingot.Labeling.AnvilClientBackend,
        default_queue_id: "queue-news"
      }
    )
  end

  # Health check endpoint (no auth required)
  scope "/", IngotWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  # Example of protected routes (uncomment to enable auth)
  # scope "/", IngotWeb do
  #   pipe_through [:browser, :require_auth]
  #
  #   live "/dashboard", DashboardLive, :index
  # end
  #
  # scope "/", IngotWeb do
  #   pipe_through [:browser, :require_labeler]
  #
  #   live "/label", LabelingLive, :index
  # end

  # Other scopes may use custom stacks.
  # scope "/api", IngotWeb do
  #   pipe_through :api
  # end
end
