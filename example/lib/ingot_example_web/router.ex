defmodule IngotExampleWeb.Router do
  use IngotExampleWeb, :router
  import Ingot.Labeling.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {IngotExampleWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", IngotExampleWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Mount Ingot labeling routes using the composable router macro
  scope "/" do
    pipe_through :browser

    labeling_routes("/labeling",
      root_layout: {IngotExampleWeb.Layouts, :root},
      config: %{
        backend: IngotExample.LabelingBackend,
        default_queue_id: "example-queue"
      }
    )
  end
end
