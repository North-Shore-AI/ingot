defmodule IngotWeb.Router do
  use IngotWeb, :router

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

  scope "/", IngotWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/label", LabelingLive, :index
    live "/dashboard", DashboardLive, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", IngotWeb do
  #   pipe_through :api
  # end
end
