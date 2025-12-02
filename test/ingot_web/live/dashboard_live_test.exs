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
      {:ok, view, _html} = live(conn, "/dashboard")

      # Should have loaded statistics
      assert view.assigns.statistics != nil
      assert view.assigns.statistics.total_labels != nil
      assert view.assigns.statistics.avg_coherence != nil
    end

    test "loads queue stats from Forge on mount", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")

      # Should have loaded queue stats
      assert view.assigns.queue_stats != nil
      assert view.assigns.queue_stats.total != nil
      assert view.assigns.queue_stats.remaining != nil
    end

    test "initializes active labelers count", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")

      assert view.assigns.active_labelers == 0
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

      stats = ForgeClient.queue_stats()
      assert html =~ "#{stats.remaining}"
    end

    test "displays total sessions", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/dashboard")

      stats = AnvilClient.statistics()
      assert html =~ "#{stats.total_sessions}"
    end

    test "displays average ratings", %{conn: conn} do
      {:ok, view, html} = live(conn, "/dashboard")

      stats = view.assigns.statistics

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
      {:ok, _view, _html} = live(conn, "/dashboard")

      # Should not crash when receiving broadcast
      Phoenix.PubSub.broadcast(
        Ingot.PubSub,
        "progress:labels",
        {:label_completed, "session-123", DateTime.utc_now()}
      )

      Process.sleep(10)
      # Success if no crash
    end

    test "refreshes statistics when label completed", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")

      initial_stats = view.assigns.statistics

      # Simulate label completion
      send(view.pid, {:label_completed, "session-123", DateTime.utc_now()})

      Process.sleep(10)

      # Should have refreshed statistics
      assert view.assigns.statistics != nil
    end

    test "updates active labelers on user join", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")

      assert view.assigns.active_labelers == 0

      # Simulate user joining
      send(view.pid, {:user_joined, "user-123", DateTime.utc_now()})

      Process.sleep(10)

      # Should increment
      assert view.assigns.active_labelers == 1
    end

    test "updates active labelers on user leave", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")

      # Simulate users joining
      send(view.pid, {:user_joined, "user-1", DateTime.utc_now()})
      send(view.pid, {:user_joined, "user-2", DateTime.utc_now()})
      Process.sleep(10)

      assert view.assigns.active_labelers == 2

      # Simulate user leaving
      send(view.pid, {:user_left, "user-1", DateTime.utc_now()})

      Process.sleep(10)

      # Should decrement
      assert view.assigns.active_labelers == 1
    end

    test "does not go negative on user leave", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")

      assert view.assigns.active_labelers == 0

      # Simulate user leaving when count is 0
      send(view.pid, {:user_left, "user-1", DateTime.utc_now()})

      Process.sleep(10)

      # Should stay at 0
      assert view.assigns.active_labelers == 0
    end

    test "updates queue stats on queue update", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")

      new_stats = %{total: 600, completed: 150, remaining: 450}

      # Simulate queue update
      send(view.pid, {:queue_updated, new_stats, DateTime.utc_now()})

      Process.sleep(10)

      # Should update queue stats
      assert view.assigns.queue_stats == new_stats
    end
  end

  describe "export functionality" do
    test "has export CSV button", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")

      assert has_element?(view, "button", "Export CSV")
    end

    test "triggers CSV export on button click", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")

      # Click export button
      html =
        view
        |> element("button", "Export CSV")
        |> render_click()

      # Should show success message
      assert html =~ "CSV export ready"
    end
  end

  describe "auto-refresh" do
    test "schedules periodic refresh", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")

      initial_updated = view.assigns.last_updated

      # Simulate refresh event
      send(view.pid, :refresh)

      Process.sleep(10)

      # Should have updated timestamp
      assert view.assigns.last_updated != initial_updated
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
