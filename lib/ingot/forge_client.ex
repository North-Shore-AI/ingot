defmodule Ingot.ForgeClient do
  @moduledoc """
  Client for interacting with Forge sample generation library.

  This is a thin wrapper that delegates all logic to Forge.
  Ingot contains no sample generation logic itself.
  """

  @doc """
  Fetch next sample from queue for the given user.

  ## Examples

      iex> ForgeClient.fetch_next_sample("user-123")
      {:ok, %{id: "sample-1", narrative_a: "...", narrative_b: "...", synthesis: "..."}}

      iex> ForgeClient.fetch_next_sample("user-123")
      {:error, :queue_empty}
  """
  def fetch_next_sample(_user_id) do
    # Mock implementation - will be replaced with actual Forge integration
    {:ok,
     %{
       id: "sample-#{:rand.uniform(1000)}",
       narrative_a:
         "Narrative A presents a perspective focusing on economic growth and technological innovation as primary drivers of progress.",
       narrative_b:
         "Narrative B emphasizes environmental sustainability and social equity as essential foundations for long-term prosperity.",
       synthesis:
         "A balanced approach recognizes that economic growth and environmental sustainability are not mutually exclusive but rather interdependent. Technological innovation can drive both economic advancement and ecological preservation when directed toward sustainable practices. Social equity ensures that the benefits of progress are shared broadly, creating stable foundations for continued development.",
       metadata: %{
         generated_at: DateTime.utc_now(),
         model: "gpt-4",
         temperature: 0.7
       }
     }}
  end

  @doc """
  Mark sample as skipped by the user.

  ## Examples

      iex> ForgeClient.skip_sample("sample-1", "user-123")
      :ok
  """
  def skip_sample(_sample_id, _user_id) do
    # Mock implementation
    :ok
  end

  @doc """
  Get queue statistics.

  ## Examples

      iex> ForgeClient.queue_stats()
      %{total: 500, completed: 47, remaining: 453}
  """
  def queue_stats do
    # Mock implementation
    %{
      total: 500,
      completed: 47,
      remaining: 453
    }
  end

  @doc """
  Generate new batch of samples.

  ## Examples

      iex> ForgeClient.generate_batch(10)
      {:ok, 10}
  """
  def generate_batch(count) do
    # Mock implementation
    {:ok, count}
  end
end
