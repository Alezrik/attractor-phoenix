defmodule AttractorPhoenixWeb.AttractorChannelTest do
  use ExUnit.Case, async: false
  import Phoenix.ChannelTest

  alias AttractorEx.HTTP.Manager
  alias AttractorPhoenixWeb.{AttractorChannel, UserSocket}

  @endpoint AttractorPhoenixWeb.Endpoint

  test "pushes a snapshot on join and forwards live pipeline updates" do
    pipeline_id = unique_pipeline_id()

    {:ok, _pipeline_id} =
      Manager.create_pipeline(AttractorPhoenix.AttractorHTTP.Manager, simple_dot(), %{},
        pipeline_id: pipeline_id,
        logs_root: unique_logs_root()
      )

    {:ok, _join_reply, _socket} =
      UserSocket
      |> socket(nil, %{})
      |> subscribe_and_join(AttractorChannel, "attractor:pipeline:#{pipeline_id}")

    assert_push "snapshot", %{"pipeline_id" => ^pipeline_id}

    :ok =
      Manager.record_event(AttractorPhoenix.AttractorHTTP.Manager, pipeline_id, %{
        type: "PipelineHeartbeat",
        status: "running"
      })

    assert_push "pipeline_event", %{"pipeline_id" => ^pipeline_id, "type" => "PipelineHeartbeat"}

    assert :ok =
             Manager.register_question(AttractorPhoenix.AttractorHTTP.Manager, pipeline_id, %{
               id: "gate",
               waiter: self(),
               ref: make_ref(),
               prompt: "Approve?"
             })

    assert_push "pipeline_event", %{
      "pipeline_id" => ^pipeline_id,
      "type" => "PipelineQuestionsUpdated",
      "questions" => [%{"id" => "gate"}]
    }
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
    "channel-" <> Integer.to_string(System.unique_integer([:positive]))
  end

  defp unique_logs_root do
    Path.join([
      "tmp",
      "attractor_channel_test",
      Integer.to_string(System.unique_integer([:positive]))
    ])
  end
end
