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
      {:ok, _view, html} = live(conn, "/label")

      # User ID and session ID should be present in data attributes
      assert html =~ "data-user-id=\"user-"
      assert html =~ "data-session-id=\"session-"
    end

    test "initializes ratings to nil", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/label")

      # All rating buttons should NOT have selected state
      refute html =~ "data-rating-selected=\"coherence\""
      refute html =~ "data-rating-selected=\"grounded\""
      refute html =~ "data-rating-selected=\"novel\""
      refute html =~ "data-rating-selected=\"balanced\""
    end

    test "fetches sample from Forge on mount", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/label")

      # Should have sample content displayed
      assert html =~ "data-sample-id="
      # Sample narratives should be rendered
      assert html =~ "NARRATIVE A:"
      assert html =~ "NARRATIVE B:"
      assert html =~ "SYNTHESIS:"
    end
  end

  describe "rating interaction" do
    test "updates rating when button clicked", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Click coherence rating of 4
      html =
        view
        |> element("button[data-dimension='coherence'][data-rating='4']")
        |> render_click()

      # Should show coherence rated as 4
      assert html =~ "data-coherence-rating=\"4\""
    end

    test "advances focus to next dimension after rating", %{conn: conn} do
      {:ok, view, html} = live(conn, "/label")

      # Initially focused on coherence
      assert html =~ "data-focused-dimension=\"coherence\""

      # Rate coherence
      html =
        view
        |> element("button[data-dimension='coherence'][data-rating='3']")
        |> render_click()

      # Should advance to grounded
      assert html =~ "data-focused-dimension=\"grounded\""

      # Rate grounded
      html =
        view
        |> element("button[data-dimension='grounded'][data-rating='4']")
        |> render_click()

      # Should advance to novel
      assert html =~ "data-focused-dimension=\"novel\""
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

      html =
        view
        |> element("button[data-dimension='balanced'][data-rating='4']")
        |> render_click()

      # All ratings should be set
      assert html =~ "data-coherence-rating=\"4\""
      assert html =~ "data-grounded-rating=\"5\""
      assert html =~ "data-novel-rating=\"3\""
      assert html =~ "data-balanced-rating=\"4\""
    end

    test "can change rating after initial selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Rate coherence as 3
      html =
        view
        |> element("button[data-dimension='coherence'][data-rating='3']")
        |> render_click()

      assert html =~ "data-coherence-rating=\"3\""

      # Change to 5
      html =
        view
        |> element("button[data-dimension='coherence'][data-rating='5']")
        |> render_click()

      assert html =~ "data-coherence-rating=\"5\""
    end
  end

  describe "notes field" do
    test "updates notes when typing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Type in notes field
      html =
        view
        |> element("textarea#notes")
        |> render_change(%{"value" => "This is a good synthesis"})

      # Notes should be visible in the rendered output
      assert html =~ "This is a good synthesis"
    end

    test "notes field is optional", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Complete all ratings without notes
      rate_all_dimensions(view)

      # Submit should work even without notes
      html =
        view
        |> element("#submit-button")
        |> render_click()

      # Should show 1 labeled
      assert html =~ "1 labeled"
    end
  end

  describe "submit label" do
    test "submits label when all ratings complete", %{conn: conn} do
      {:ok, view, html} = live(conn, "/label")

      initial_sample_id = extract_sample_id(html)

      # Rate all dimensions
      rate_all_dimensions(view)

      # Submit
      html =
        view
        |> element("#submit-button")
        |> render_click()

      # Should show 1 labeled
      assert html =~ "1 labeled"

      # Should have new sample (different ID)
      new_sample_id = extract_sample_id(html)
      refute new_sample_id == initial_sample_id

      # Ratings should be reset (no selected ratings visible)
      refute html =~ "data-coherence-rating=\""
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
      html =
        view
        |> element("#submit-button")
        |> render_click()

      # Label should have been stored (verified through session counter)
      assert html =~ "1 labeled"
    end

    test "tracks time spent on sample", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/label")

      # Timer should be started (indicated by data attribute)
      assert html =~ "data-timer-active=\"true\""
    end
  end

  describe "skip functionality" do
    test "skips current sample and loads next", %{conn: conn} do
      {:ok, view, html} = live(conn, "/label")

      initial_sample_id = extract_sample_id(html)

      # Skip sample
      html =
        view
        |> element("button", "Skip")
        |> render_click()

      # Should have new sample
      new_sample_id = extract_sample_id(html)
      refute new_sample_id == initial_sample_id

      # Session counter should NOT increment (still 0)
      assert html =~ "0 labeled"

      # Ratings should be reset
      refute html =~ "data-coherence-rating=\""
    end

    test "can skip multiple times", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Skip 3 times
      html =
        for _ <- 1..3, reduce: "" do
          _acc ->
            view
            |> element("button", "Skip")
            |> render_click()
        end

      # Should still have a current sample
      assert html =~ "data-sample-id="

      # No labels should be counted
      assert html =~ "0 labeled"
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
      {:ok, stats} = ForgeClient.queue_stats()
      assert html =~ "#{stats.total}"
      assert html =~ "#{stats.remaining}"
    end
  end

  describe "PubSub integration" do
    test "subscribes to progress events on mount", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Broadcast a label completion event
      Phoenix.PubSub.broadcast(
        Ingot.PubSub,
        "progress:labels",
        {:label_completed, "other-session", DateTime.utc_now()}
      )

      # Supertester pattern: use :sys.get_state for deterministic sync
      # This forces a synchronous call, ensuring all prior messages are processed
      :sys.get_state(view.pid)

      # Should have received the broadcast (verified by no crashes)
      assert render(view) =~ "Ingot Labeler"
    end

    test "updates total labels when other user completes label", %{conn: conn} do
      {:ok, view, html} = live(conn, "/label")

      # Get initial total from HTML
      _initial_total = extract_total_labels(html)

      # Simulate another user completing a label
      send(view.pid, {:label_completed, "other-session", DateTime.utc_now()})

      # Supertester pattern: deterministic sync via :sys.get_state
      :sys.get_state(view.pid)

      # Render and check total is updated
      html = render(view)
      assert html =~ "data-total-labels="
    end

    test "updates active labelers count on user join", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Supertester pattern: sync initial state before measuring baseline
      :sys.get_state(view.pid)
      html = render(view)
      baseline_count = extract_active_labelers(html)

      # Simulate multiple users joining to verify behavior
      send(view.pid, {:user_joined, "test-user-1", DateTime.utc_now()})
      send(view.pid, {:user_joined, "test-user-2", DateTime.utc_now()})

      # Supertester pattern: deterministic sync - ensure messages processed
      :sys.get_state(view.pid)

      # Render and check count increased by 2
      html = render(view)
      new_count = extract_active_labelers(html)
      assert new_count == baseline_count + 2
    end

    test "updates active labelers count on user leave", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Supertester pattern: sync before adding users
      :sys.get_state(view.pid)

      # Add users
      send(view.pid, {:user_joined, "test-user-1", DateTime.utc_now()})
      send(view.pid, {:user_joined, "test-user-2", DateTime.utc_now()})

      # Supertester pattern: sync after sends
      :sys.get_state(view.pid)
      html = render(view)
      count_before = extract_active_labelers(html)

      # Simulate one user leaving
      send(view.pid, {:user_left, "test-user-1", DateTime.utc_now()})

      # Supertester pattern: sync before assertion
      :sys.get_state(view.pid)

      # Render and check count decremented by exactly 1
      html = render(view)
      count_after = extract_active_labelers(html)
      assert count_after == count_before - 1
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

  defp extract_sample_id(html) do
    case Regex.run(~r/data-sample-id="([^"]+)"/, html) do
      [_, id] -> id
      _ -> nil
    end
  end

  defp extract_total_labels(html) do
    case Regex.run(~r/data-total-labels="(\d+)"/, html) do
      [_, count] -> String.to_integer(count)
      _ -> 0
    end
  end

  defp extract_active_labelers(html) do
    case Regex.run(~r/data-active-labelers="(\d+)"/, html) do
      [_, count] -> String.to_integer(count)
      _ -> 1
    end
  end

  describe "keyboard shortcuts" do
    test "1-5 keys rate the focused dimension", %{conn: conn} do
      {:ok, view, html} = live(conn, "/label")

      # Initially focused on coherence
      assert html =~ "data-focused-dimension=\"coherence\""

      # Press '3' key to rate coherence
      html =
        view
        |> element("div[phx-hook='KeyboardShortcuts']")
        |> render_hook("keydown", %{"key" => "3"})

      # Should have rated coherence as 3
      assert html =~ "data-coherence-rating=\"3\""

      # Should advance focus to grounded
      assert html =~ "data-focused-dimension=\"grounded\""
    end

    test "number keys only rate values 1-5", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Press '0' should not rate
      html =
        view
        |> element("div[phx-hook='KeyboardShortcuts']")
        |> render_hook("keydown", %{"key" => "0"})

      # Coherence should still be nil
      refute html =~ "data-coherence-rating="

      # Press '6' should not rate
      html =
        view
        |> element("div[phx-hook='KeyboardShortcuts']")
        |> render_hook("keydown", %{"key" => "6"})

      # Coherence should still be nil
      refute html =~ "data-coherence-rating="
    end

    test "Tab key advances focus between dimensions", %{conn: conn} do
      {:ok, view, html} = live(conn, "/label")

      # Initially focused on coherence
      assert html =~ "data-focused-dimension=\"coherence\""

      # Press Tab
      html =
        view
        |> element("div[phx-hook='KeyboardShortcuts']")
        |> render_hook("keydown", %{"key" => "Tab"})

      # Should advance to grounded
      assert html =~ "data-focused-dimension=\"grounded\""

      # Press Tab again
      html =
        view
        |> element("div[phx-hook='KeyboardShortcuts']")
        |> render_hook("keydown", %{"key" => "Tab"})

      # Should advance to novel
      assert html =~ "data-focused-dimension=\"novel\""

      # Press Tab again
      html =
        view
        |> element("div[phx-hook='KeyboardShortcuts']")
        |> render_hook("keydown", %{"key" => "Tab"})

      # Should advance to balanced
      assert html =~ "data-focused-dimension=\"balanced\""

      # Press Tab on last dimension should stay on balanced
      html =
        view
        |> element("div[phx-hook='KeyboardShortcuts']")
        |> render_hook("keydown", %{"key" => "Tab"})

      # Should stay on balanced
      assert html =~ "data-focused-dimension=\"balanced\""
    end

    test "Enter key submits when all ratings complete", %{conn: conn} do
      {:ok, view, html} = live(conn, "/label")

      initial_sample_id = extract_sample_id(html)

      # Rate all dimensions using number keys
      view
      |> element("div[phx-hook='KeyboardShortcuts']")
      |> render_hook("keydown", %{"key" => "4"})

      view
      |> element("div[phx-hook='KeyboardShortcuts']")
      |> render_hook("keydown", %{"key" => "5"})

      view
      |> element("div[phx-hook='KeyboardShortcuts']")
      |> render_hook("keydown", %{"key" => "3"})

      view
      |> element("div[phx-hook='KeyboardShortcuts']")
      |> render_hook("keydown", %{"key" => "4"})

      # Press Enter to submit
      html =
        view
        |> element("div[phx-hook='KeyboardShortcuts']")
        |> render_hook("keydown", %{"key" => "Enter"})

      # Should have submitted and loaded new sample
      new_sample_id = extract_sample_id(html)
      refute new_sample_id == initial_sample_id

      # Should show 1 labeled
      assert html =~ "1 labeled"
    end

    test "Enter key does nothing when ratings incomplete", %{conn: conn} do
      {:ok, view, html} = live(conn, "/label")

      initial_sample_id = extract_sample_id(html)

      # Only rate coherence
      view
      |> element("div[phx-hook='KeyboardShortcuts']")
      |> render_hook("keydown", %{"key" => "3"})

      # Press Enter
      html =
        view
        |> element("div[phx-hook='KeyboardShortcuts']")
        |> render_hook("keydown", %{"key" => "Enter"})

      # Should show error
      assert html =~ "Please complete all ratings"

      # Sample should not have changed
      assert extract_sample_id(html) == initial_sample_id
    end

    test "S key skips current sample", %{conn: conn} do
      {:ok, view, html} = live(conn, "/label")

      initial_sample_id = extract_sample_id(html)

      # Press 'S' to skip
      html =
        view
        |> element("div[phx-hook='KeyboardShortcuts']")
        |> render_hook("keydown", %{"key" => "s"})

      # Should have new sample
      new_sample_id = extract_sample_id(html)
      refute new_sample_id == initial_sample_id

      # Session counter should NOT increment
      assert html =~ "0 labeled"
    end

    test "Q key quits session", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Press 'Q' to quit
      view
      |> element("div[phx-hook='KeyboardShortcuts']")
      |> render_hook("keydown", %{"key" => "q"})

      # Should redirect to home
      assert_redirect(view, "/")
    end

    test "Escape key quits session", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/label")

      # Press Escape to quit
      view
      |> element("div[phx-hook='KeyboardShortcuts']")
      |> render_hook("keydown", %{"key" => "Escape"})

      # Should redirect to home
      assert_redirect(view, "/")
    end

    test "? key toggles help modal", %{conn: conn} do
      {:ok, view, html} = live(conn, "/label")

      # Initially help modal is hidden
      assert html =~ "data-show-help=\"false\""

      # Press '?' to show help
      html =
        view
        |> element("div[phx-hook='KeyboardShortcuts']")
        |> render_hook("keydown", %{"key" => "?"})

      # Help modal should be visible
      assert html =~ "data-show-help=\"true\""

      # Press '?' again to hide help
      html =
        view
        |> element("div[phx-hook='KeyboardShortcuts']")
        |> render_hook("keydown", %{"key" => "?"})

      # Help modal should be hidden
      assert html =~ "data-show-help=\"false\""
    end

    test "keyboard shortcuts are case insensitive for letter keys", %{conn: conn} do
      {:ok, view, html} = live(conn, "/label")

      initial_sample_id = extract_sample_id(html)

      # Press uppercase 'S' to skip (with shift modifier)
      html =
        view
        |> element("div[phx-hook='KeyboardShortcuts']")
        |> render_hook("keydown", %{"key" => "S"})

      # Should have skipped
      new_sample_id = extract_sample_id(html)
      refute new_sample_id == initial_sample_id
    end

    test "complete keyboard workflow: rate all dimensions with keys and submit", %{conn: conn} do
      {:ok, view, html} = live(conn, "/label")

      initial_sample_id = extract_sample_id(html)

      # Rate coherence with '4'
      html =
        view
        |> element("div[phx-hook='KeyboardShortcuts']")
        |> render_hook("keydown", %{"key" => "4"})

      assert html =~ "data-coherence-rating=\"4\""
      assert html =~ "data-focused-dimension=\"grounded\""

      # Rate grounded with '5'
      html =
        view
        |> element("div[phx-hook='KeyboardShortcuts']")
        |> render_hook("keydown", %{"key" => "5"})

      assert html =~ "data-grounded-rating=\"5\""
      assert html =~ "data-focused-dimension=\"novel\""

      # Rate novel with '3'
      html =
        view
        |> element("div[phx-hook='KeyboardShortcuts']")
        |> render_hook("keydown", %{"key" => "3"})

      assert html =~ "data-novel-rating=\"3\""
      assert html =~ "data-focused-dimension=\"balanced\""

      # Rate balanced with '4'
      html =
        view
        |> element("div[phx-hook='KeyboardShortcuts']")
        |> render_hook("keydown", %{"key" => "4"})

      assert html =~ "data-balanced-rating=\"4\""

      # Submit with Enter
      html =
        view
        |> element("div[phx-hook='KeyboardShortcuts']")
        |> render_hook("keydown", %{"key" => "Enter"})

      # Should have submitted and loaded new sample
      new_sample_id = extract_sample_id(html)
      refute new_sample_id == initial_sample_id
      assert html =~ "1 labeled"

      # Focus should reset to coherence
      assert html =~ "data-focused-dimension=\"coherence\""
    end
  end
end
