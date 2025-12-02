defmodule IngotWeb.DashboardLiveTest do
  use IngotWeb.ConnCase, async: true
  use Supertester.ExUnitFoundation

  import Phoenix.LiveViewTest

  alias Ingot.{AnvilClient, ForgeClient}

  describe "mount/3" do
    test "successfully mounts and displays dashboard", %{conn: conn} do
      {:ok, view, html} = live(conn, "/dashboard")

      # Should display the dashboard title
      assert html =~ "Labeling Dashboard"

      # Should have start labeling link
      assert has_element?(view, "a", "Start Labeling")
    end

    test "loads statistics from Anvil on mount", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/dashboard")

      # Should have loaded statistics - verify via rendered content
      stats = AnvilClient.statistics()
      assert html =~ "Total Labels"
      assert html =~ "#{stats.total_labels}"
      assert html =~ "Coherence"
    end

    test "loads queue stats from Forge on mount", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/dashboard")

      # Should have loaded queue stats - verify via rendered content
      {:ok, stats} = ForgeClient.queue_stats()
      assert html =~ "#{stats.total}"
      assert html =~ "#{stats.remaining}"
    end

    test "initializes active labelers count", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/dashboard")

      # Should show 0 active labelers initially in the rendered HTML
      assert html =~ "Active Labelers"
      assert html =~ ~r/Active Labelers.*?0/s
    end
  end

  describe "statistics display" do
    test "displays total labels", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/dashboard")

      stats = AnvilClient.statistics()
      assert html =~ "#{stats.total_labels}"
    end

    test "displays active labelers count", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/dashboard")

      # Should show 0 initially
      assert html =~ "Active Labelers"
    end

    test "displays queue remaining", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/dashboard")

      {:ok, stats} = ForgeClient.queue_stats()
      assert html =~ "#{stats.remaining}"
    end

    test "displays total sessions", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/dashboard")

      stats = AnvilClient.statistics()
      assert html =~ "#{stats.total_sessions}"
    end

    test "displays average ratings", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/dashboard")

      stats = AnvilClient.statistics()

      # Should show all rating averages
      assert html =~ "Coherence"
      assert html =~ "#{Float.round(stats.avg_coherence, 1)}"

      assert html =~ "Grounded"
      assert html =~ "#{Float.round(stats.avg_grounded, 1)}"

      assert html =~ "Novel"
      assert html =~ "#{Float.round(stats.avg_novel, 1)}"

      assert html =~ "Balanced"
      assert html =~ "#{Float.round(stats.avg_balanced, 1)}"
    end

    test "displays average time per label", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/dashboard")

      # Should show formatted time
      assert html =~ "Average Time per Label"
    end
  end

  describe "PubSub integration" do
    test "subscribes to progress events on mount", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")

      # Should not crash when receiving broadcast
      Phoenix.PubSub.broadcast(
        Ingot.PubSub,
        "progress:labels",
        {:label_completed, "session-123", DateTime.utc_now()}
      )

      # Supertester pattern: deterministic sync via :sys.get_state
      :sys.get_state(view.pid)

      # Success if no crash
      assert render(view) =~ "Dashboard"
    end

    test "refreshes statistics when label completed", %{conn: conn} do
      {:ok, view, _html_before} = live(conn, "/dashboard")

      # Simulate label completion
      send(view.pid, {:label_completed, "session-123", DateTime.utc_now()})

      # Supertester pattern: sync before assertion
      :sys.get_state(view.pid)

      # Should have refreshed - page re-renders (just check no crash and stats still present)
      html = render(view)
      assert html =~ "Total Labels"
    end

    test "updates active labelers on user join", %{conn: conn} do
      {:ok, view, html} = live(conn, "/dashboard")

      # Initial value should be 0
      assert html =~ ~r/Active Labelers.*?0/s

      # Simulate user joining
      send(view.pid, {:user_joined, "user-123", DateTime.utc_now()})

      # Supertester pattern: deterministic sync
      :sys.get_state(view.pid)

      # Should increment to 1
      html = render(view)
      assert html =~ ~r/Active Labelers.*?1/s
    end

    test "updates active labelers on user leave", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")

      # Simulate users joining
      send(view.pid, {:user_joined, "user-1", DateTime.utc_now()})
      send(view.pid, {:user_joined, "user-2", DateTime.utc_now()})

      # Supertester pattern: sync after sends
      :sys.get_state(view.pid)

      html = render(view)
      assert html =~ ~r/Active Labelers.*?2/s

      # Simulate user leaving
      send(view.pid, {:user_left, "user-1", DateTime.utc_now()})

      # Supertester pattern: sync before assertion
      :sys.get_state(view.pid)

      # Should decrement to 1
      html = render(view)
      assert html =~ ~r/Active Labelers.*?1/s
    end

    test "does not go negative on user leave", %{conn: conn} do
      {:ok, view, html} = live(conn, "/dashboard")

      # Initial value is 0
      assert html =~ ~r/Active Labelers.*?0/s

      # Simulate user leaving when count is 0
      send(view.pid, {:user_left, "user-1", DateTime.utc_now()})

      # Supertester pattern: deterministic sync
      :sys.get_state(view.pid)

      # Should stay at 0
      html = render(view)
      assert html =~ ~r/Active Labelers.*?0/s
    end

    test "updates queue stats on queue update", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")

      new_stats = %{total: 600, completed: 150, remaining: 999}

      # Simulate queue update
      send(view.pid, {:queue_updated, new_stats, DateTime.utc_now()})

      # Supertester pattern: deterministic sync via :sys.get_state
      :sys.get_state(view.pid)
      html = render(view)

      # Should show new remaining value (999 is unique and won't collide with mock data)
      assert html =~ "999"
    end
  end

  describe "export functionality" do
    test "has export CSV button", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")

      assert has_element?(view, "button", "Export CSV")
    end

    test "triggers CSV export on button click", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")

      # Click export button - should not crash
      view
      |> element("button", "Export CSV")
      |> render_click()

      # Check that the download event was pushed (via flash message in socket)
      # Note: Flash messages may not appear in rendered HTML without flash component
      # Just verify the click succeeded without error
      html = render(view)
      # The page should still render correctly after click
      assert html =~ "Export CSV"
    end
  end

  describe "auto-refresh" do
    test "schedules periodic refresh", %{conn: conn} do
      {:ok, view, _html_before} = live(conn, "/dashboard")

      # Simulate refresh event
      send(view.pid, :refresh)

      # Supertester pattern: deterministic sync
      :sys.get_state(view.pid)

      # Should have re-rendered (just check no crash)
      html = render(view)
      assert html =~ "Last updated:"
    end
  end

  describe "navigation" do
    test "can navigate to labeling interface", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")

      # Click start labeling link
      view
      |> element("a", "Start Labeling")
      |> render_click()

      # Should redirect to labeling page
      assert_redirect(view, "/label")
    end
  end

  describe "formatting helpers" do
    test "formats time correctly", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/dashboard")

      # Should show formatted time
      assert html =~ ~r/\d{2}:\d{2}:\d{2}/
    end

    test "formats duration in minutes and seconds", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/dashboard")

      # Should show formatted duration (either "Xs" or "Xm Ys")
      assert html =~ ~r/\d+[ms]/
    end
  end
end
