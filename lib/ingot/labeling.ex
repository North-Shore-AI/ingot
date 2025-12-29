defmodule Ingot.Labeling do
  @moduledoc """
  Composable labeling feature module for Phoenix applications.

  This module provides a portable labeling interface that can be embedded
  in any Phoenix application. It includes:

  - LiveViews for labeling and dashboard
  - Component behaviours for customization
  - Backend behaviour for pluggable data sources
  - Router macro for easy mounting

  ## Installation

  Add to your `mix.exs` dependencies:

      {:ingot, path: "../ingot"}

  Or from Hex:

      {:ingot, "~> 0.2.0"}

  ## Usage

  1. Implement the backend behaviour:

      defmodule MyApp.LabelingBackend do
        @behaviour Ingot.Labeling.Backend

        @impl true
        def get_next_assignment(queue_id, user_id, opts) do
          # Your implementation
        end

        @impl true
        def submit_label(assignment_id, label, opts) do
          # Your implementation
        end

        @impl true
        def get_queue_stats(queue_id, opts) do
          # Your implementation
        end
      end

  2. Mount routes in your router:

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

  ## Components

  The labeling interface can be customized by implementing:

  - `Ingot.SampleRenderer` - Custom sample visualization
  - `Ingot.LabelFormRenderer` - Custom label input widgets

  See module documentation for details.
  """

  @doc """
  Returns the version of the Ingot labeling module.
  """
  def version, do: "0.2.0"
end
