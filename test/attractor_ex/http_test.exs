defmodule AttractorEx.HTTPTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias AttractorEx.HTTP.Manager
  alias AttractorEx.HTTP.Router

  @router_opts Router.init([])

  setup do
    start_supervised!({Manager, name: AttractorEx.HTTP.Manager, store_root: unique_store_root()})
    start_supervised!({Registry, keys: :duplicate, name: AttractorEx.HTTP.Registry})
    :ok
  end

  test "creates a pipeline and exposes status, context, checkpoint, graph formats, and SSE events" do
    dot = """
    digraph attractor {
      graph [goal="Ship feature"]
      start [shape=Mdiamond]
      plan [shape=box, prompt="Plan for $goal"]
      done [shape=Msquare]
      start -> plan -> done
    }
    """

    conn =
      conn(:post, "/pipelines", Jason.encode!(%{"dot" => dot, "context" => %{"ticket" => "A-1"}}))
      |> put_req_header("content-type", "application/json")
      |> Router.call(@router_opts)

    assert conn.status == 202
    %{"pipeline_id" => pipeline_id} = Jason.decode!(conn.resp_body)

    wait_for(fn ->
      case Manager.get_pipeline(AttractorEx.HTTP.Manager, pipeline_id) do
        {:ok, %{status: :success, task_pid: task_pid}} when is_pid(task_pid) ->
          {:ok, task_pid}

        {:ok, %{status: "success", task_pid: task_pid}} when is_pid(task_pid) ->
          {:ok, task_pid}

        _ ->
          :retry
      end
    end)

    status_conn = Router.call(conn(:get, "/pipelines/#{pipeline_id}"), @router_opts)
    assert status_conn.status == 200
    assert %{"status" => "success"} = Jason.decode!(status_conn.resp_body)

    context_conn = Router.call(conn(:get, "/pipelines/#{pipeline_id}/context"), @router_opts)
    assert context_conn.status == 200

    assert %{"context" => %{"ticket" => "A-1", "run_id" => ^pipeline_id}} =
             Jason.decode!(context_conn.resp_body)

    checkpoint_conn =
      Router.call(conn(:get, "/pipelines/#{pipeline_id}/checkpoint"), @router_opts)

    assert checkpoint_conn.status == 200

    assert %{"checkpoint" => %{"current_node" => "done", "completed_nodes" => completed}} =
             Jason.decode!(checkpoint_conn.resp_body)

    assert "done" in completed

    graph_conn = Router.call(conn(:get, "/pipelines/#{pipeline_id}/graph"), @router_opts)
    assert graph_conn.status == 200
    assert [content_type | _] = get_resp_header(graph_conn, "content-type")
    assert String.starts_with?(content_type, "image/svg+xml")
    assert get_resp_header(graph_conn, "cache-control") == ["no-store"]
    assert get_resp_header(graph_conn, "x-content-type-options") == ["nosniff"]
    assert graph_conn.resp_body =~ "Attractor Pipeline"
    assert graph_conn.resp_body =~ "Goal: Ship feature"
    assert graph_conn.resp_body =~ "marker-end=\"url(#arrowhead)\""
    assert graph_conn.resp_body =~ "node node-codergen"
    refute graph_conn.resp_body =~ "<foreignObject"

    dot_graph_conn =
      Router.call(conn(:get, "/pipelines/#{pipeline_id}/graph?format=dot"), @router_opts)

    assert dot_graph_conn.status == 200
    assert [dot_content_type | _] = get_resp_header(dot_graph_conn, "content-type")
    assert String.starts_with?(dot_content_type, "text/vnd.graphviz")

    assert get_resp_header(dot_graph_conn, "content-disposition") == [
             "inline; filename=\"pipeline.dot\""
           ]

    assert dot_graph_conn.resp_body =~ "digraph attractor"

    json_graph_conn =
      Router.call(conn(:get, "/pipelines/#{pipeline_id}/graph?format=json"), @router_opts)

    assert json_graph_conn.status == 200

    assert %{"graph" => %{"id" => "attractor", "nodes" => nodes, "edges" => edges}} =
             Jason.decode!(json_graph_conn.resp_body)

    assert Map.has_key?(nodes, "plan")
    assert is_list(edges)

    mermaid_graph_conn =
      Router.call(conn(:get, "/pipelines/#{pipeline_id}/graph?format=mermaid"), @router_opts)

    assert mermaid_graph_conn.status == 200
    assert [mermaid_content_type | _] = get_resp_header(mermaid_graph_conn, "content-type")
    assert String.starts_with?(mermaid_content_type, "text/plain")
    assert mermaid_graph_conn.resp_body =~ "flowchart TD"
    assert mermaid_graph_conn.resp_body =~ "start -->|"

    text_graph_conn =
      Router.call(conn(:get, "/pipelines/#{pipeline_id}/graph?format=text"), @router_opts)

    assert text_graph_conn.status == 200
    assert [text_content_type | _] = get_resp_header(text_graph_conn, "content-type")
    assert String.starts_with?(text_content_type, "text/plain")
    assert text_graph_conn.resp_body =~ "Graph: attractor"
    assert text_graph_conn.resp_body =~ "Nodes:"
    assert text_graph_conn.resp_body =~ "Edges:"

    invalid_graph_conn =
      Router.call(conn(:get, "/pipelines/#{pipeline_id}/graph?format=png"), @router_opts)

    assert invalid_graph_conn.status == 400

    assert %{"error" => "unsupported graph format", "supported_formats" => formats} =
             Jason.decode!(invalid_graph_conn.resp_body)

    assert "mermaid" in formats
    assert "text" in formats

    events_conn = Router.call(conn(:get, "/pipelines/#{pipeline_id}/events"), @router_opts)
    assert events_conn.status == 200
    assert events_conn.resp_body =~ "event: PipelineStarted"
    assert events_conn.resp_body =~ "event: PipelineCompleted"

    replay_conn =
      Router.call(
        conn(:get, "/pipelines/#{pipeline_id}/events?stream=false&after=1"),
        @router_opts
      )

    assert replay_conn.status == 200
    assert %{"events" => replayed_events} = Jason.decode!(replay_conn.resp_body)
    assert Enum.all?(replayed_events, &(Map.fetch!(&1, "sequence") > 1))
  end

  test "rejects pipeline creation requests without dot source" do
    conn =
      conn(:post, "/pipelines", Jason.encode!(%{"context" => %{"ticket" => "A-2"}}))
      |> put_req_header("content-type", "application/json")
      |> Router.call(@router_opts)

    assert conn.status == 400
    assert %{"error" => "pipeline dot source is required"} = Jason.decode!(conn.resp_body)
  end

  test "rejects oversized JSON pipeline submissions with an explicit 413 response" do
    oversized_dot = String.duplicate("a", 1_000_001)

    conn =
      conn(:post, "/pipelines", Jason.encode!(%{"dot" => oversized_dot}))
      |> put_req_header("content-type", "application/json")
      |> Router.call(@router_opts)

    assert conn.status == 413

    assert %{"error" => "request body too large", "max_bytes" => 1_000_000} =
             Jason.decode!(conn.resp_body)

    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  test "exposes pending questions and accepts answers for wait.human nodes" do
    dot = """
    digraph attractor {
      start [shape=Mdiamond]
      gate [shape=hexagon, prompt="Approve release?", human.timeout="5s"]
      done [shape=Msquare]
      retry [shape=box, prompt="Retry release"]
      start -> gate
      gate -> done [label="[A] Approve"]
      gate -> retry [label="[R] Retry"]
      retry -> done
    }
    """

    conn =
      conn(:post, "/pipelines", Jason.encode!(%{"dot" => dot}))
      |> put_req_header("content-type", "application/json")
      |> Router.call(@router_opts)

    assert conn.status == 202
    %{"pipeline_id" => pipeline_id} = Jason.decode!(conn.resp_body)

    {:ok, pipeline} = Manager.get_pipeline(AttractorEx.HTTP.Manager, pipeline_id)
    task_pid = pipeline.task_pid

    questions =
      wait_for(fn ->
        case Manager.pending_questions(AttractorEx.HTTP.Manager, pipeline_id) do
          {:ok, [_question | _] = pending} -> {:ok, pending}
          _ -> :retry
        end
      end)

    [question] = questions
    assert question.id == "gate"
    assert question.text == "Approve release?"
    assert length(question.options) == 2

    questions_conn = Router.call(conn(:get, "/pipelines/#{pipeline_id}/questions"), @router_opts)
    assert questions_conn.status == 200

    assert questions_conn.resp_body =~ "\"question_id\"" or
             questions_conn.resp_body =~ "\"id\":\"gate\""

    answer_conn =
      conn(
        :post,
        "/pipelines/#{pipeline_id}/questions/gate/answer",
        Jason.encode!(%{"answer" => "A"})
      )
      |> put_req_header("content-type", "application/json")
      |> Router.call(@router_opts)

    assert answer_conn.status == 202

    ref = Process.monitor(task_pid)

    wait_for(fn ->
      case Manager.get_pipeline(AttractorEx.HTTP.Manager, pipeline_id) do
        {:ok, %{status: :success}} -> {:ok, :done}
        {:ok, %{status: "success"}} -> {:ok, :done}
        _ -> :retry
      end
    end)

    assert_receive {:DOWN, ^ref, :process, ^task_pid, reason}, 1_000
    assert reason in [:normal, :noproc]

    status_conn = Router.call(conn(:get, "/pipelines/#{pipeline_id}"), @router_opts)
    assert status_conn.status == 200
    assert %{"status" => "success"} = Jason.decode!(status_conn.resp_body)

    final_questions_conn =
      Router.call(conn(:get, "/pipelines/#{pipeline_id}/questions"), @router_opts)

    assert %{"questions" => []} = Jason.decode!(final_questions_conn.resp_body)
  end

  test "exposes inferred question metadata for wait.human HTTP questions" do
    dot = """
    digraph attractor {
      start [shape=Mdiamond]
      gate [
        shape=hexagon,
        prompt="Pick release actions",
        human.timeout="1d",
        human.multiple=true,
        human.required=false,
        human.input="checkbox"
      ]
      done [shape=Msquare]
      retry [shape=box, prompt="Retry release"]
      start -> gate
      gate -> done [label="[A] Approve"]
      gate -> retry [label="[R] Retry"]
      retry -> done
    }
    """

    conn =
      conn(:post, "/pipelines", Jason.encode!(%{"dot" => dot}))
      |> put_req_header("content-type", "application/json")
      |> Router.call(@router_opts)

    assert conn.status == 202
    %{"pipeline_id" => pipeline_id} = Jason.decode!(conn.resp_body)

    wait_for(fn ->
      case Manager.pending_questions(AttractorEx.HTTP.Manager, pipeline_id) do
        {:ok, [_question | _]} -> {:ok, :ready}
        _ -> :retry
      end
    end)

    questions_conn = Router.call(conn(:get, "/pipelines/#{pipeline_id}/questions"), @router_opts)
    assert questions_conn.status == 200

    assert %{
             "questions" => [
               %{
                 "id" => "gate",
                 "type" => "MULTIPLE_CHOICE",
                 "multiple" => true,
                 "required" => false,
                 "timeout_seconds" => 86_400.0,
                 "metadata" => %{
                   "question_type" => "MULTIPLE_CHOICE",
                   "timeout" => "1d",
                   "multiple" => true,
                   "required" => false,
                   "input_mode" => "checkbox",
                   "choice_count" => 2
                 },
                 "options" => [
                   %{"key" => "A", "label" => "[A] Approve", "to" => "done"},
                   %{"key" => "R", "label" => "[R] Retry", "to" => "retry"}
                 ]
               }
             ]
           } = Jason.decode!(questions_conn.resp_body)
  end

  test "supports spec-compatible run, status, and answer HTTP aliases" do
    dot = """
    digraph attractor {
      start [shape=Mdiamond]
      gate [shape=hexagon, prompt="Approve release?", human.timeout="5s"]
      done [shape=Msquare]
      retry [shape=box, prompt="Retry release"]
      start -> gate
      gate -> done [label="[A] Approve"]
      gate -> retry [label="[R] Retry"]
      retry -> done
    }
    """

    run_conn =
      conn(:post, "/run", Jason.encode!(%{"dot_source" => dot}))
      |> put_req_header("content-type", "application/json")
      |> Router.call(@router_opts)

    assert run_conn.status == 202
    %{"pipeline_id" => pipeline_id} = Jason.decode!(run_conn.resp_body)

    wait_for(fn ->
      case Manager.pending_questions(AttractorEx.HTTP.Manager, pipeline_id) do
        {:ok, [_question | _]} -> {:ok, :ready}
        _ -> :retry
      end
    end)

    status_conn =
      Router.call(conn(:get, "/status?pipeline_id=#{pipeline_id}"), @router_opts)

    assert status_conn.status == 200

    assert %{"pipeline_id" => ^pipeline_id, "status" => "running"} =
             Jason.decode!(status_conn.resp_body)

    answer_conn =
      conn(
        :post,
        "/answer",
        Jason.encode!(%{"pipeline_id" => pipeline_id, "question_id" => "gate", "value" => "A"})
      )
      |> put_req_header("content-type", "application/json")
      |> Router.call(@router_opts)

    assert answer_conn.status == 202

    assert %{"accepted" => true, "pipeline_id" => ^pipeline_id, "question_id" => "gate"} =
             Jason.decode!(answer_conn.resp_body)

    wait_for(fn ->
      case Manager.get_pipeline(AttractorEx.HTTP.Manager, pipeline_id) do
        {:ok, %{status: :success}} -> {:ok, :done}
        {:ok, %{status: "success"}} -> {:ok, :done}
        _ -> :retry
      end
    end)

    final_status_conn =
      Router.call(conn(:get, "/status?id=#{pipeline_id}"), @router_opts)

    assert final_status_conn.status == 200

    assert %{"pipeline_id" => ^pipeline_id, "status" => "success"} =
             Jason.decode!(final_status_conn.resp_body)
  end

  defp wait_for(fun, attempts \\ 100)

  defp wait_for(_fun, 0), do: flunk("condition was not met in time")

  defp wait_for(fun, attempts) do
    case fun.() do
      {:ok, value} ->
        value

      :retry ->
        receive do
        after
          10 -> wait_for(fun, attempts - 1)
        end
    end
  end

  defp unique_store_root do
    Path.join([
      "tmp",
      "http_router_store_test",
      Integer.to_string(System.unique_integer([:positive]))
    ])
  end
end
