defmodule Ingot.Labeling.RouterTest do
  use ExUnit.Case, async: true

  # Create a minimal test router
  defmodule TestBackend do
    @behaviour Ingot.Labeling.Backend

    @impl true
    def get_next_assignment(_queue_id, _user_id, _opts), do: {:ok, %{}}

    @impl true
    def submit_label(_assignment_id, _label, _opts), do: {:ok, %{}}

    @impl true
    def get_queue_stats(_queue_id, _opts), do: {:ok, %{}}
  end

  defmodule TestRouter do
    use Phoenix.Router
    import Ingot.Labeling.Router
    import Phoenix.LiveView.Router

    pipeline :browser do
      plug :accepts, ["html"]
    end

    scope "/" do
      pipe_through :browser

      labeling_routes("/labeling",
        config: %{backend: Ingot.Labeling.RouterTest.TestBackend}
      )
    end
  end

  test "generates dashboard route" do
    routes = TestRouter.__routes__()

    dashboard_route =
      Enum.find(routes, fn route ->
        route.path == "/labeling" &&
          get_in(route.metadata, [:phoenix_live_view]) |> elem(0) == Ingot.Labeling.DashboardLive
      end)

    assert dashboard_route, "Dashboard route not found"
    assert dashboard_route.plug_opts == :index
  end

  test "generates labeling interface route" do
    routes = TestRouter.__routes__()

    labeling_route =
      Enum.find(routes, fn route ->
        route.path == "/labeling/queues/:queue_id/label" &&
          get_in(route.metadata, [:phoenix_live_view]) |> elem(0) == Ingot.Labeling.LabelingLive
      end)

    assert labeling_route, "Labeling interface route not found"
    assert labeling_route.plug_opts == :label
  end

  test "raises error when backend not provided" do
    assert_raise ArgumentError, ~r/requires a :backend/, fn ->
      defmodule BadRouter do
        use Phoenix.Router
        import Ingot.Labeling.Router
        import Phoenix.LiveView.Router

        scope "/" do
          labeling_routes("/labeling", config: %{})
        end
      end
    end
  end
end
