defmodule Ingot.Labeling.Router do
  @moduledoc """
  Router macro for mounting Ingot labeling routes in any Phoenix application.

  This macro provides a composable way to add labeling functionality to any
  Phoenix app by defining LiveView routes within a `live_session`.

  ## Usage

      # In your host app's router.ex
      defmodule MyAppWeb.Router do
        use MyAppWeb, :router
        import Ingot.Labeling.Router

        scope "/" do
          pipe_through [:browser, :require_authenticated]

          labeling_routes "/labeling",
            on_mount: [MyAppWeb.AuthLive],
            root_layout: {MyAppWeb.Layouts, :app},
            config: %{backend: MyApp.LabelingBackend}
        end
      end

  ## Options

  - `:on_mount` - List of on_mount hooks for authentication/authorization
  - `:root_layout` - Root layout tuple (e.g., `{MyAppWeb.Layouts, :root}`)
  - `:session_layout` - Session layout tuple (optional, overrides root_layout for session)
  - `:config` - Configuration map passed to LiveViews via session
    - `:backend` - Backend module implementing `Ingot.Labeling.Backend` (required)
    - `:tenant_id` - Default tenant ID (optional)
    - Any other app-specific configuration

  ## Routes Created

  - `GET [path]` - Dashboard (queue stats)
  - `GET [path]/queues/:queue_id/label` - Labeling interface

  ## Examples

      # Basic usage with authentication
      labeling_routes "/labeling",
        on_mount: [MyAppWeb.RequireAuth],
        config: %{backend: MyApp.LabelingBackend}

      # Custom layout and tenant
      labeling_routes "/annotation",
        root_layout: {MyAppWeb.Layouts, :admin},
        config: %{
          backend: MyApp.LabelingBackend,
          tenant_id: "production"
        }

      # Multiple authentication hooks
      labeling_routes "/labeling",
        on_mount: [MyAppWeb.LoadCurrentUser, MyAppWeb.RequireLabeler],
        config: %{backend: MyApp.LabelingBackend}
  """

  @doc """
  Defines labeling routes under the given path.
  """
  defmacro labeling_routes(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      import Phoenix.LiveView.Router

      # Extract options
      on_mount = Keyword.get(opts, :on_mount, [])
      root_layout = Keyword.get(opts, :root_layout)
      session_layout = Keyword.get(opts, :session_layout)
      config = Keyword.get(opts, :config, %{})

      # Validate required configuration
      unless is_map(config) and Map.has_key?(config, :backend) do
        raise ArgumentError, """
        labeling_routes requires a :backend in :config option.

        Example:
          labeling_routes "/labeling",
            config: %{backend: MyApp.LabelingBackend}
        """
      end

      # Build live_session options
      session_opts = [
        on_mount: on_mount,
        session: %{"labeling_config" => config}
      ]

      # Add root_layout if provided
      session_opts =
        if session_layout || root_layout do
          Keyword.put(session_opts, :root_layout, session_layout || root_layout)
        else
          session_opts
        end

      # Use live_session for isolation and configuration injection
      live_session :ingot_labeling, session_opts do
        # Dashboard route
        live path, Ingot.Labeling.DashboardLive, :index

        # Labeling interface route
        live "#{path}/queues/:queue_id/label", Ingot.Labeling.LabelingLive, :label
      end
    end
  end
end
