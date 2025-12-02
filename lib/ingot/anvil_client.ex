defmodule Ingot.AnvilClient do
  @moduledoc """
  Client for interacting with Anvil label storage library.

  This is a thin wrapper that delegates all logic to Anvil.
  Ingot contains no label storage logic itself.
  """

  @doc """
  Store a completed label.

  ## Examples

      iex> label = %{sample_id: "s1", ratings: %{coherence: 4}}
      iex> AnvilClient.store_label(label)
      {:ok, label}
  """
  def store_label(label) do
    # Mock implementation - will be replaced with actual Anvil integration
    # For now, just validate and return
    if valid_label?(label) do
      {:ok, label}
    else
      {:error, :invalid_label}
    end
  end

  @doc """
  Get total count of all labels.

  ## Examples

      iex> AnvilClient.total_labels()
      47
  """
  def total_labels do
    # Mock implementation
    47
  end

  @doc """
  Get all labels for a specific session.

  ## Examples

      iex> AnvilClient.session_labels("session-123")
      [%{sample_id: "s1", ratings: %{coherence: 4}}, ...]
  """
  def session_labels(_session_id) do
    # Mock implementation
    []
  end

  @doc """
  Export all labels as CSV.

  ## Examples

      iex> AnvilClient.export_csv()
      {:ok, "sample_id,coherence,grounded,novel,balanced\\n..."}
  """
  def export_csv do
    # Mock implementation
    {:ok, "sample_id,coherence,grounded,novel,balanced,notes\n"}
  end

  @doc """
  Get labeling statistics.

  ## Examples

      iex> AnvilClient.statistics()
      %{total_labels: 47, avg_coherence: 3.8, ...}
  """
  def statistics do
    # Mock implementation
    %{
      total_labels: 47,
      avg_coherence: 3.8,
      avg_grounded: 4.1,
      avg_novel: 3.2,
      avg_balanced: 3.9,
      total_sessions: 5,
      avg_time_per_label_ms: 45_000
    }
  end

  # Private helpers

  defp valid_label?(label) do
    required_keys = [:sample_id, :session_id, :user_id, :ratings, :labeled_at]
    Enum.all?(required_keys, &Map.has_key?(label, &1))
  end
end
