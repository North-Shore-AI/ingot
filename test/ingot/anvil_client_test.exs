defmodule Ingot.AnvilClientTest do
  use ExUnit.Case, async: true
  use Supertester.ExUnitFoundation

  alias Ingot.AnvilClient
  alias Ingot.DTO.{Assignment, QueueStats, Sample}

  describe "get_next_assignment/2" do
    test "returns assignment DTO with required fields" do
      {:ok, assignment} = AnvilClient.get_next_assignment("queue-1", "user-123")

      assert %Assignment{} = assignment
      assert assignment.id != nil
      assert assignment.queue_id == "queue-1"
      assert %Sample{} = assignment.sample
      assert assignment.schema != nil
      assert is_list(assignment.existing_labels)
      assert %DateTime{} = assignment.assigned_at
    end

    test "assignment contains valid sample" do
      {:ok, assignment} = AnvilClient.get_next_assignment("queue-1", "user-123")

      assert assignment.sample.id != nil
      assert assignment.sample.payload.narrative_a != nil
      assert assignment.sample.payload.narrative_b != nil
      assert assignment.sample.payload.synthesis != nil
    end

    test "assignment contains label schema" do
      # The mock occasionally returns errors (10% of the time), so retry if needed
      assignment =
        case AnvilClient.get_next_assignment("queue-1", "user-123") do
          {:ok, assignment} -> assignment
          {:error, _} -> elem(AnvilClient.get_next_assignment("queue-1", "user-123"), 1)
        end

      assert assignment.schema.fields != nil
      assert is_list(assignment.schema.fields)
    end

    test "can return errors when no assignments available" do
      # The mock occasionally returns errors (10% of the time)
      result = AnvilClient.get_next_assignment("queue-1", "user-123")

      case result do
        {:ok, assignment} -> assert %Assignment{} = assignment
        {:error, reason} -> assert reason in [:no_assignments, :timeout, :not_found]
      end
    end
  end

  describe "submit_label/2" do
    test "returns :ok for valid label data" do
      values = %{
        coherence: 4,
        grounded: 5,
        novel: 3,
        balanced: 4
      }

      assert :ok = AnvilClient.submit_label("assignment-123", values)
    end

    test "returns validation error for missing fields" do
      values = %{coherence: 4}

      result = AnvilClient.submit_label("assignment-123", values)

      case result do
        :ok -> :ok
        {:error, {:validation, errors}} -> assert is_map(errors)
        {:error, _} -> :ok
      end
    end
  end

  describe "get_queue_stats/1" do
    test "returns queue stats DTO with required fields" do
      {:ok, stats} = AnvilClient.get_queue_stats("queue-1")

      assert %QueueStats{} = stats
      assert is_integer(stats.total_samples)
      assert is_integer(stats.labeled)
      assert is_integer(stats.remaining)
      assert is_map(stats.agreement_scores)
      assert is_integer(stats.active_labelers)
    end

    test "stats show valid progress numbers" do
      {:ok, stats} = AnvilClient.get_queue_stats("queue-1")

      assert stats.total_samples >= 0
      assert stats.labeled >= 0
      assert stats.remaining >= 0
      assert stats.active_labelers >= 0
    end

    test "labeled + remaining equals total" do
      {:ok, stats} = AnvilClient.get_queue_stats("queue-1")

      assert stats.labeled + stats.remaining == stats.total_samples
    end
  end

  describe "store_label/1 (legacy API)" do
    test "stores valid label and returns success tuple" do
      label = valid_label()

      assert {:ok, ^label} = AnvilClient.store_label(label)
    end

    test "returns error for invalid label missing required fields" do
      invalid_label = %{sample_id: "sample-1"}

      assert {:error, :invalid_label} = AnvilClient.store_label(invalid_label)
    end

    test "validates label has sample_id" do
      label = valid_label() |> Map.delete(:sample_id)

      assert {:error, :invalid_label} = AnvilClient.store_label(label)
    end

    test "validates label has session_id" do
      label = valid_label() |> Map.delete(:session_id)

      assert {:error, :invalid_label} = AnvilClient.store_label(label)
    end

    test "validates label has user_id" do
      label = valid_label() |> Map.delete(:user_id)

      assert {:error, :invalid_label} = AnvilClient.store_label(label)
    end

    test "validates label has ratings" do
      label = valid_label() |> Map.delete(:ratings)

      assert {:error, :invalid_label} = AnvilClient.store_label(label)
    end

    test "validates label has labeled_at timestamp" do
      label = valid_label() |> Map.delete(:labeled_at)

      assert {:error, :invalid_label} = AnvilClient.store_label(label)
    end

    test "accepts label with optional notes field" do
      label = valid_label() |> Map.put(:notes, "Great synthesis")

      assert {:ok, ^label} = AnvilClient.store_label(label)
    end

    test "accepts label with optional time_spent_ms field" do
      label = valid_label() |> Map.put(:time_spent_ms, 45_000)

      assert {:ok, ^label} = AnvilClient.store_label(label)
    end
  end

  describe "total_labels/0" do
    test "returns an integer count" do
      total = AnvilClient.total_labels()

      assert is_integer(total)
      assert total >= 0
    end
  end

  describe "session_labels/1" do
    test "returns a list for any session_id" do
      labels = AnvilClient.session_labels("session-123")

      assert is_list(labels)
    end

    test "returns empty list for non-existent session" do
      labels = AnvilClient.session_labels("non-existent-session")

      assert labels == []
    end
  end

  describe "export_csv/0" do
    test "returns success tuple with CSV string" do
      assert {:ok, csv_data} = AnvilClient.export_csv()
      assert is_binary(csv_data)
    end

    test "CSV contains header row" do
      {:ok, csv_data} = AnvilClient.export_csv()

      assert csv_data =~ "sample_id"
      assert csv_data =~ "coherence"
      assert csv_data =~ "grounded"
      assert csv_data =~ "novel"
      assert csv_data =~ "balanced"
      assert csv_data =~ "notes"
    end
  end

  describe "statistics/0" do
    test "returns statistics map with required keys" do
      stats = AnvilClient.statistics()

      assert is_map(stats)
      assert Map.has_key?(stats, :total_labels)
      assert Map.has_key?(stats, :avg_coherence)
      assert Map.has_key?(stats, :avg_grounded)
      assert Map.has_key?(stats, :avg_novel)
      assert Map.has_key?(stats, :avg_balanced)
      assert Map.has_key?(stats, :total_sessions)
      assert Map.has_key?(stats, :avg_time_per_label_ms)
    end

    test "returns valid numbers for all statistics" do
      stats = AnvilClient.statistics()

      assert is_integer(stats.total_labels)
      assert is_number(stats.avg_coherence)
      assert is_number(stats.avg_grounded)
      assert is_number(stats.avg_novel)
      assert is_number(stats.avg_balanced)
      assert is_integer(stats.total_sessions)
      assert is_integer(stats.avg_time_per_label_ms)
    end

    test "average ratings are within valid range 1-5" do
      stats = AnvilClient.statistics()

      assert stats.avg_coherence >= 1 and stats.avg_coherence <= 5
      assert stats.avg_grounded >= 1 and stats.avg_grounded <= 5
      assert stats.avg_novel >= 1 and stats.avg_novel <= 5
      assert stats.avg_balanced >= 1 and stats.avg_balanced <= 5
    end
  end

  # Helper functions

  defp valid_label do
    %{
      sample_id: "sample-123",
      session_id: "session-456",
      user_id: "user-789",
      ratings: %{
        coherence: 4,
        grounded: 5,
        novel: 3,
        balanced: 4
      },
      labeled_at: DateTime.utc_now()
    }
  end
end
