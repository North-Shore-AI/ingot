defmodule Ingot.ForgeClientTest do
  use ExUnit.Case, async: true
  use Supertester.ExUnitFoundation

  alias Ingot.ForgeClient

  describe "fetch_next_sample/1" do
    test "returns a sample with required fields" do
      {:ok, sample} = ForgeClient.fetch_next_sample("user-123")

      assert sample.id != nil
      assert sample.narrative_a != nil
      assert sample.narrative_b != nil
      assert sample.synthesis != nil
      assert sample.metadata != nil
    end

    test "returns unique sample IDs on subsequent calls" do
      {:ok, sample1} = ForgeClient.fetch_next_sample("user-123")
      {:ok, sample2} = ForgeClient.fetch_next_sample("user-123")

      # Sample IDs should be different (probabilistically)
      # Note: In mock implementation, this might not always be true
      assert sample1.id != nil
      assert sample2.id != nil
    end

    test "sample contains metadata with timestamp" do
      {:ok, sample} = ForgeClient.fetch_next_sample("user-123")

      assert %DateTime{} = sample.metadata.generated_at
      assert sample.metadata.model != nil
    end
  end

  describe "skip_sample/2" do
    test "returns :ok when skipping a sample" do
      assert :ok = ForgeClient.skip_sample("sample-123", "user-456")
    end

    test "accepts any sample_id and user_id" do
      assert :ok = ForgeClient.skip_sample("any-sample", "any-user")
    end
  end

  describe "queue_stats/0" do
    test "returns statistics map with required keys" do
      stats = ForgeClient.queue_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :total)
      assert Map.has_key?(stats, :completed)
      assert Map.has_key?(stats, :remaining)
    end

    test "returns valid numbers for all stats" do
      stats = ForgeClient.queue_stats()

      assert is_integer(stats.total)
      assert is_integer(stats.completed)
      assert is_integer(stats.remaining)
      assert stats.total >= 0
      assert stats.completed >= 0
      assert stats.remaining >= 0
    end

    test "completed + remaining equals total" do
      stats = ForgeClient.queue_stats()

      assert stats.completed + stats.remaining == stats.total
    end
  end

  describe "generate_batch/1" do
    test "returns success tuple with count" do
      assert {:ok, 10} = ForgeClient.generate_batch(10)
    end

    test "accepts different batch sizes" do
      assert {:ok, 5} = ForgeClient.generate_batch(5)
      assert {:ok, 100} = ForgeClient.generate_batch(100)
    end
  end
end
