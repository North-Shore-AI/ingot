defmodule Ingot.Labeling.BackendTest do
  use ExUnit.Case, async: true

  alias Ingot.Labeling.AnvilClientBackend

  describe "AnvilClientBackend" do
    test "implements Ingot.Labeling.Backend behaviour" do
      behaviours = AnvilClientBackend.__info__(:attributes)[:behaviour] || []
      assert Ingot.Labeling.Backend in behaviours
    end

    test "delegates get_next_assignment to AnvilClient" do
      # Verify the function can be called (delegates to configured adapter)
      # The actual behavior is tested in AnvilClient tests
      assert {:ok, _assignment} =
               AnvilClientBackend.get_next_assignment("queue-1", "user-1", [])
    end

    test "delegates submit_label to AnvilClient" do
      # Verify the function can be called
      label = %{value: "test"}
      assert {:ok, _label} = AnvilClientBackend.submit_label("asn-1", label, [])
    end

    test "delegates get_queue_stats to AnvilClient" do
      # Verify the function can be called
      assert {:ok, _stats} = AnvilClientBackend.get_queue_stats("queue-1", [])
    end

    test "delegates check_queue_access to AnvilClient" do
      # Verify the function can be called
      assert {:ok, _has_access} =
               AnvilClientBackend.check_queue_access("user-1", "queue-1", [])
    end
  end

  describe "Backend behaviour contract" do
    defmodule MockBackend do
      @behaviour Ingot.Labeling.Backend

      @impl true
      def get_next_assignment(queue_id, user_id, opts) do
        send(self(), {:get_next_assignment, queue_id, user_id, opts})

        {:ok,
         %LabelingIR.Assignment{
           id: "test",
           queue_id: queue_id,
           tenant_id: "test",
           sample: %LabelingIR.Sample{
             id: "smp-1",
             tenant_id: "test",
             pipeline_id: "pipe-1",
             namespace: "test",
             payload: %{},
             artifacts: [],
             metadata: %{},
             created_at: DateTime.utc_now()
           },
           schema: %LabelingIR.Schema{
             id: "schema-1",
             tenant_id: "test",
             namespace: "test",
             fields: [],
             metadata: %{}
           },
           namespace: "test",
           lineage_ref: "test",
           metadata: %{}
         }}
      end

      @impl true
      def submit_label(assignment_id, label, opts) do
        send(self(), {:submit_label, assignment_id, label, opts})
        {:ok, label}
      end

      @impl true
      def get_queue_stats(queue_id, opts) do
        send(self(), {:get_queue_stats, queue_id, opts})
        {:ok, %{remaining: 10, labeled: 5}}
      end

      @impl true
      def check_queue_access(user_id, queue_id, opts) do
        send(self(), {:check_queue_access, user_id, queue_id, opts})
        {:ok, true}
      end
    end

    test "backend can be called for assignments" do
      result = MockBackend.get_next_assignment("queue-1", "user-1", [])
      assert {:ok, assignment} = result
      assert assignment.queue_id == "queue-1"
      assert_received {:get_next_assignment, "queue-1", "user-1", []}
    end

    test "backend can be called to submit labels" do
      label = %{value: "test"}
      {:ok, returned} = MockBackend.submit_label("asn-1", label, [])
      assert returned == label
      assert_received {:submit_label, "asn-1", ^label, []}
    end

    test "backend can be called for stats" do
      {:ok, stats} = MockBackend.get_queue_stats("queue-1", [])
      assert stats.remaining == 10
      assert_received {:get_queue_stats, "queue-1", []}
    end

    test "backend can check access" do
      {:ok, has_access} = MockBackend.check_queue_access("user-1", "queue-1", [])
      assert has_access == true
      assert_received {:check_queue_access, "user-1", "queue-1", []}
    end
  end
end
