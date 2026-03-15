defmodule AttractorExPhx.PubSubTest do
  use ExUnit.Case, async: false

  alias AttractorEx.HTTP.Manager
  alias AttractorExPhx.PubSub

  setup do
    manager = start_supervised!({AttractorEx.HTTP.Manager, store_root: unique_store_root()})
    _pubsub = start_supervised!({Phoenix.PubSub, name: __MODULE__.PubSub})

    bridge =
      start_supervised!(
        {PubSub, manager: manager, pubsub_server: __MODULE__.PubSub, name: __MODULE__.Bridge}
      )

    {:ok, pipeline_id} =
      Manager.create_pipeline(manager, simple_dot(), %{},
        pipeline_id: unique_pipeline_id(),
        logs_root: unique_logs_root()
      )

    [manager: manager, bridge: bridge, pipeline_id: pipeline_id]
  end

  test "returns a snapshot and republishes manager events over Phoenix PubSub", %{
    manager: manager,
    bridge: bridge,
    pipeline_id: pipeline_id
  } do
    assert {:ok, snapshot} =
             PubSub.subscribe_pipeline(pipeline_id,
               bridge: bridge,
               pubsub_server: __MODULE__.PubSub
             )

    assert snapshot["pipeline_id"] == pipeline_id
    assert is_list(snapshot["events"])

    :ok =
      Manager.record_event(manager, pipeline_id, %{type: "PipelineHeartbeat", status: "running"})

    assert_receive {:attractor_ex_event,
                    %{"pipeline_id" => ^pipeline_id, "type" => "PipelineHeartbeat"}}

    assert :ok =
             Manager.register_question(manager, pipeline_id, %{
               id: "gate",
               waiter: self(),
               ref: make_ref(),
               prompt: "Approve?"
             })

    assert_receive {:attractor_ex_event,
                    %{
                      "pipeline_id" => ^pipeline_id,
                      "type" => "PipelineQuestionsUpdated",
                      "questions" => [%{"id" => "gate"}]
                    }}
  end

  test "supports replay-filtered subscription snapshots", %{
    bridge: bridge,
    pipeline_id: pipeline_id
  } do
    assert {:ok, snapshot} =
             PubSub.subscribe_pipeline(pipeline_id,
               bridge: bridge,
               pubsub_server: __MODULE__.PubSub,
               after_sequence: 1
             )

    assert Enum.all?(snapshot["events"], &(Map.fetch!(&1, "sequence") > 1))
  end

  defp simple_dot do
    """
    digraph attractor {
      start [shape=Mdiamond]
      hello [shape=parallelogram, tool_command="echo hello"]
      done [shape=Msquare]
      start -> hello
      hello -> done
    }
    """
  end

  defp unique_pipeline_id do
    "pubsub-" <> Integer.to_string(System.unique_integer([:positive]))
  end

  defp unique_logs_root do
    Path.join([
      "tmp",
      "attractor_ex_phx_pubsub_test",
      Integer.to_string(System.unique_integer([:positive]))
    ])
  end

  defp unique_store_root do
    Path.join([
      "tmp",
      "attractor_ex_phx_store_test",
      Integer.to_string(System.unique_integer([:positive]))
    ])
  end
end
