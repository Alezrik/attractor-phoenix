defmodule AttractorEx.Conformance.StateTest do
  use ExUnit.Case, async: false

  alias AttractorEx.HTTP.Manager
  alias AttractorExTest.ConformanceFixtures

  test "persists run state and replayable events across manager restart" do
    store_root = ConformanceFixtures.unique_store_root("state")
    manager_name = Module.concat(__MODULE__, PersistedManager)
    reloaded_name = Module.concat(__MODULE__, ReloadedManager)

    manager =
      start_supervised!(%{
        id: :conformance_state_manager,
        start: {Manager, :start_link, [[name: manager_name, store_root: store_root]]}
      })

    {:ok, pipeline_id} =
      Manager.create_pipeline(
        manager,
        ConformanceFixtures.transport_dot(),
        %{"ticket" => "CONF-1"},
        pipeline_id: "conformance-state",
        logs_root: ConformanceFixtures.unique_logs_root("state")
      )

    ConformanceFixtures.wait_until(fn ->
      match?({:ok, %{status: :success}}, Manager.get_pipeline(manager, pipeline_id))
    end)

    assert {:ok, events_before} = Manager.pipeline_events(manager, pipeline_id)
    assert events_before != []

    GenServer.stop(manager)

    reloaded =
      start_supervised!(%{
        id: :conformance_state_manager_reloaded,
        start: {Manager, :start_link, [[name: reloaded_name, store_root: store_root]]}
      })

    assert {:ok, %{status: :success, context: %{"run_id" => ^pipeline_id}}} =
             Manager.get_pipeline(reloaded, pipeline_id)

    assert {:ok, replayed} = Manager.replay_events(reloaded, pipeline_id, after_sequence: 1)
    assert Enum.all?(replayed, &(Map.fetch!(&1, "sequence") > 1))
  end
end
