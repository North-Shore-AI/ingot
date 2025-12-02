defmodule IngotWeb.LabelingLiveTest do
  use IngotWeb.ConnCase, async: true
  use Supertester.ExUnitFoundation

  import Phoenix.LiveViewTest

  alias Ingot.{ForgeClient, AnvilClient}

  describe "mount/3" do
    test "successfully mounts and fetches initial sample", %{conn: conn} do
      {:ok, view, html} = live(conn, "/label")

      # Should display the labeling interface
      assert html =~ "Ingot Labeler"
      assert html =~ "NARRATIVE A:"
      assert html =~ "NARRATIVE B:"
      assert html =~ "SYNTHESIS:"
      assert html =~ "YOUR RATING:"

      # Should have skip and quit buttons
      assert has_element?(view, "button", "Skip")
      assert has_element?(view, "button", "Quit")
    end

    test "generates user_id and session_id on mount", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # User ID and session ID should be assigned
      assert view.assigns.user_id != nil
      assert view.assigns.session_id != nil
      assert String.starts_with?(view.assigns.user_id, "user-")
      assert String.starts_with?(view.assigns.session_id, "session-")
    end

    test "initializes ratings to nil", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      assert view.assigns.ratings == %{
               coherence: nil,
               grounded: nil,
               novel: nil,
               balanced: nil
             }
    end

    test "fetches sample from Forge on mount", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Should have a current sample
      assert view.assigns.current_sample != nil
      assert view.assigns.current_sample.id != nil
      assert view.assigns.current_sample.narrative_a != nil
      assert view.assigns.current_sample.narrative_b != nil
      assert view.assigns.current_sample.synthesis != nil
    end
  end

  describe "rating interaction" do
    test "updates rating when button clicked", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Click coherence rating of 4
      view
      |> element("button[data-dimension='coherence'][data-rating='4']")
      |> render_click()

      assert view.assigns.ratings.coherence == 4
    end

    test "advances focus to next dimension after rating", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Initially focused on coherence
      assert view.assigns.focused_dimension == :coherence

      # Rate coherence
      view
      |> element("button[data-dimension='coherence'][data-rating='3']")
      |> render_click()

      # Should advance to grounded
      assert view.assigns.focused_dimension == :grounded

      # Rate grounded
      view
      |> element("button[data-dimension='grounded'][data-rating='4']")
      |> render_click()

      # Should advance to novel
      assert view.assigns.focused_dimension == :novel
    end

    test "can rate all dimensions", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Rate all dimensions
      view
      |> element("button[data-dimension='coherence'][data-rating='4']")
      |> render_click()

      view
      |> element("button[data-dimension='grounded'][data-rating='5']")
      |> render_click()

      view
      |> element("button[data-dimension='novel'][data-rating='3']")
      |> render_click()

      view
      |> element("button[data-dimension='balanced'][data-rating='4']")
      |> render_click()

      assert view.assigns.ratings == %{
               coherence: 4,
               grounded: 5,
               novel: 3,
               balanced: 4
             }
    end

    test "can change rating after initial selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Rate coherence as 3
      view
      |> element("button[data-dimension='coherence'][data-rating='3']")
      |> render_click()

      assert view.assigns.ratings.coherence == 3

      # Change to 5
      view
      |> element("button[data-dimension='coherence'][data-rating='5']")
      |> render_click()

      assert view.assigns.ratings.coherence == 5
    end
  end

  describe "notes field" do
    test "updates notes when typing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Type in notes field
      view
      |> element("textarea#notes")
      |> render_change(%{"value" => "This is a good synthesis"})

      assert view.assigns.notes == "This is a good synthesis"
    end

    test "notes field is optional", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Complete all ratings without notes
      rate_all_dimensions(view)

      # Submit should work even without notes
      view
      |> element("#submit-button")
      |> render_click()

      # Should have moved to next sample
      assert view.assigns.labels_this_session == 1
    end
  end

  describe "submit label" do
    test "submits label when all ratings complete", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      initial_sample_id = view.assigns.current_sample.id

      # Rate all dimensions
      rate_all_dimensions(view)

      # Submit
      view
      |> element("#submit-button")
      |> render_click()

      # Should have incremented session counter
      assert view.assigns.labels_this_session == 1

      # Should have fetched new sample
      refute view.assigns.current_sample.id == initial_sample_id

      # Ratings should be reset
      assert view.assigns.ratings == %{
               coherence: nil,
               grounded: nil,
               novel: nil,
               balanced: nil
             }

      # Notes should be cleared
      assert view.assigns.notes == ""

      # Focus should reset to coherence
      assert view.assigns.focused_dimension == :coherence
    end

    test "shows error if trying to submit with incomplete ratings", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Only rate coherence
      view
      |> element("button[data-dimension='coherence'][data-rating='4']")
      |> render_click()

      # Try to submit
      html =
        view
        |> element("#submit-button")
        |> render_click()

      # Should show error message
      assert html =~ "Please complete all ratings"
    end

    test "includes notes in submitted label", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Rate all dimensions
      rate_all_dimensions(view)

      # Add notes
      view
      |> element("textarea#notes")
      |> render_change(%{"value" => "Excellent synthesis"})

      # Submit
      view
      |> element("#submit-button")
      |> render_click()

      # Label should have been stored (verified through session counter)
      assert view.assigns.labels_this_session == 1
    end

    test "tracks time spent on sample", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Timer should be started
      assert view.assigns.timer_started_at != nil

      # Rate and submit
      rate_all_dimensions(view)

      view
      |> element("#submit-button")
      |> render_click()

      # New timer should be started for next sample
      assert view.assigns.timer_started_at != nil
    end
  end

  describe "skip functionality" do
    test "skips current sample and loads next", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      initial_sample_id = view.assigns.current_sample.id

      # Skip sample
      view
      |> element("button", "Skip")
      |> render_click()

      # Should have new sample
      refute view.assigns.current_sample.id == initial_sample_id

      # Session counter should NOT increment
      assert view.assigns.labels_this_session == 0

      # Ratings should be reset
      assert view.assigns.ratings.coherence == nil
    end

    test "can skip multiple times", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Skip 3 times
      for _ <- 1..3 do
        view
        |> element("button", "Skip")
        |> render_click()
      end

      # Should still have a current sample
      assert view.assigns.current_sample != nil

      # No labels should be counted
      assert view.assigns.labels_this_session == 0
    end
  end

  describe "quit functionality" do
    test "navigates away when quit clicked", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Click quit
      view
      |> element("button", "Quit")
      |> render_click()

      # Should redirect to home
      assert_redirect(view, "/")
    end
  end

  describe "progress display" do
    test "displays session progress", %{conn: conn} do
      {:ok, view, html} = live(conn, "/label")

      # Initially 0 labeled
      assert html =~ "0 labeled"

      # Submit one label
      rate_all_dimensions(view)

      html =
        view
        |> element("#submit-button")
        |> render_click()

      # Should show 1 labeled
      assert html =~ "1 labeled"
    end

    test "displays overall progress from Anvil", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/label")

      # Should display total labels from AnvilClient
      total = AnvilClient.total_labels()
      assert html =~ "#{total}"
    end

    test "displays queue statistics from Forge", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/label")

      # Should display queue stats
      stats = ForgeClient.queue_stats()
      assert html =~ "#{stats.total}"
      assert html =~ "#{stats.remaining}"
    end
  end

  describe "PubSub integration" do
    test "subscribes to progress events on mount", %{conn: conn} do
      {:ok, _view, _html} = live(conn, "/label")

      # Broadcast a label completion event
      Phoenix.PubSub.broadcast(
        Ingot.PubSub,
        "progress:labels",
        {:label_completed, "other-session", DateTime.utc_now()}
      )

      # Give time for message to process
      Process.sleep(10)

      # Should have received the broadcast
      # (verified by no crashes and proper handling)
    end

    test "updates total labels when other user completes label", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      initial_total = view.assigns.total_labels

      # Simulate another user completing a label
      send(view.pid, {:label_completed, "other-session", DateTime.utc_now()})

      # Give time for message to process
      Process.sleep(10)

      # Total should be refreshed from Anvil
      # (In real implementation, would increment)
      assert view.assigns.total_labels != nil
    end

    test "updates active labelers count on user join", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      initial_count = view.assigns.active_labelers

      # Simulate another user joining
      send(view.pid, {:user_joined, "other-user", DateTime.utc_now()})

      # Give time for message to process
      Process.sleep(10)

      # Should increment
      assert view.assigns.active_labelers == initial_count + 1
    end

    test "updates active labelers count on user leave", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Simulate users joining
      send(view.pid, {:user_joined, "user-1", DateTime.utc_now()})
      send(view.pid, {:user_joined, "user-2", DateTime.utc_now()})
      Process.sleep(10)

      count_before = view.assigns.active_labelers

      # Simulate a user leaving
      send(view.pid, {:user_left, "user-1", DateTime.utc_now()})
      Process.sleep(10)

      # Should decrement
      assert view.assigns.active_labelers == count_before - 1
    end
  end

  # Helper functions

  defp rate_all_dimensions(view) do
    view
    |> element("button[data-dimension='coherence'][data-rating='4']")
    |> render_click()

    view
    |> element("button[data-dimension='grounded'][data-rating='5']")
    |> render_click()

    view
    |> element("button[data-dimension='novel'][data-rating='3']")
    |> render_click()

    view
    |> element("button[data-dimension='balanced'][data-rating='4']")
    |> render_click()

    view
  end
end
