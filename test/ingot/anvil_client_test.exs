defmodule Ingot.AnvilClientTest do
  use ExUnit.Case, async: true
  use Supertester.ExUnitFoundation

  alias Ingot.AnvilClient

  describe "store_label/1" do
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
