defmodule AttractorEx.HTTPTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias AttractorEx.HTTP.Manager
  alias AttractorEx.HTTP.Router

  @router_opts Router.init([])

  setup do
    start_supervised!({Manager, name: AttractorEx.HTTP.Manager})
    start_supervised!({Registry, keys: :duplicate, name: AttractorEx.HTTP.Registry})
    :ok
  end

  test "creates a pipeline and exposes status, context, checkpoint, graph, and SSE events" do
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

    {:ok, pipeline} = Manager.get_pipeline(AttractorEx.HTTP.Manager, pipeline_id)
    task_pid = pipeline.task_pid
    ref = Process.monitor(task_pid)
    assert_receive {:DOWN, ^ref, :process, ^task_pid, :normal}

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
    assert graph_conn.resp_body =~ "Attractor Pipeline"

    dot_graph_conn =
      Router.call(conn(:get, "/pipelines/#{pipeline_id}/graph?format=dot"), @router_opts)

    assert dot_graph_conn.status == 200
    assert [dot_content_type | _] = get_resp_header(dot_graph_conn, "content-type")
    assert String.starts_with?(dot_content_type, "text/vnd.graphviz")
    assert dot_graph_conn.resp_body =~ "digraph attractor"

    json_graph_conn =
      Router.call(conn(:get, "/pipelines/#{pipeline_id}/graph?format=json"), @router_opts)

    assert json_graph_conn.status == 200

    assert %{"graph" => %{"id" => "attractor", "nodes" => nodes, "edges" => edges}} =
             Jason.decode!(json_graph_conn.resp_body)

    assert Map.has_key?(nodes, "plan")
    assert is_list(edges)

    events_conn = Router.call(conn(:get, "/pipelines/#{pipeline_id}/events"), @router_opts)
    assert events_conn.status == 200
    assert events_conn.resp_body =~ "event: PipelineStarted"
    assert events_conn.resp_body =~ "event: PipelineCompleted"
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
    assert_receive {:DOWN, ^ref, :process, ^task_pid, :normal}

    status_conn = Router.call(conn(:get, "/pipelines/#{pipeline_id}"), @router_opts)
    assert status_conn.status == 200
    assert %{"status" => "success"} = Jason.decode!(status_conn.resp_body)

    final_questions_conn =
      Router.call(conn(:get, "/pipelines/#{pipeline_id}/questions"), @router_opts)

    assert %{"questions" => []} = Jason.decode!(final_questions_conn.resp_body)
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
end
