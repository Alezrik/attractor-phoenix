defmodule AttractorEx.HTTPManagerTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias AttractorEx.HTTP
  alias AttractorEx.HTTP.Manager
  alias AttractorEx.HTTP.Router

  setup do
    start_supervised!({Manager, name: AttractorEx.HTTP.Manager, store_root: unique_store_root()})
    start_supervised!({Registry, keys: :duplicate, name: AttractorEx.HTTP.Registry})
    %{manager: AttractorEx.HTTP.Manager, registry: AttractorEx.HTTP.Registry}
  end

  test "manager accessors return not_found for unknown pipelines", %{manager: manager} do
    assert {:error, :not_found} = Manager.get_pipeline(manager, "missing")
    assert {:error, :not_found} = Manager.pipeline_graph(manager, "missing")
    assert {:error, :not_found} = Manager.pipeline_context(manager, "missing")
    assert {:error, :not_found} = Manager.pipeline_checkpoint(manager, "missing")
    assert {:error, :not_found} = Manager.pipeline_events(manager, "missing")
    assert {:error, :not_found} = Manager.pending_questions(manager, "missing")
    assert {:error, :not_found} = Manager.submit_answer(manager, "missing", "q1", "A")
    assert {:error, :not_found} = Manager.subscribe(manager, "missing", self())
    assert {:error, :not_found} = Manager.cancel(manager, "missing")
    assert {:error, :not_found} = Manager.register_question(manager, "missing", %{id: "q1"})
  end

  test "manager records events, updates pipeline state, and manages question answers", %{
    manager: manager
  } do
    {:ok, pipeline_id} =
      Manager.create_pipeline(
        manager,
        "digraph { start [shape=Mdiamond] done [shape=Msquare] start -> done }",
        %{},
        pipeline_id: "unit-pipeline"
      )

    assert :ok = Manager.subscribe(manager, pipeline_id, self())

    event = %{
      type: "CheckpointSaved",
      checkpoint: %{"current_node" => "plan"},
      context: %{status: "ok"}
    }

    Manager.record_event(manager, pipeline_id, event)
    assert_receive {:pipeline_event, received}
    assert received["type"] == "CheckpointSaved"
    assert received["pipeline_id"] == pipeline_id

    question = %{id: "gate", ref: make_ref(), waiter: self(), text: "Approve?"}
    assert :ok = Manager.register_question(manager, pipeline_id, question)

    assert {:ok, [%{id: "gate", text: "Approve?"}]} =
             Manager.pending_questions(manager, pipeline_id)

    assert :ok = Manager.submit_answer(manager, pipeline_id, "gate", "A")
    assert_receive {:pipeline_answer, _, "A"}
    assert {:ok, []} = Manager.pending_questions(manager, pipeline_id)

    :ok = Manager.register_question(manager, pipeline_id, question)
    Manager.timeout_question(manager, pipeline_id, "gate")
    wait_until(fn -> match?({:ok, []}, Manager.pending_questions(manager, pipeline_id)) end)

    send(Process.whereis(manager), {:pipeline_finished, pipeline_id, {:error, %{error: "boom"}}})

    wait_until(fn ->
      match?(
        {:ok, %{status: :fail, error: %{"error" => "boom"}}},
        Manager.get_pipeline(manager, pipeline_id)
      )
    end)
  end

  test "manager exposes success-path accessors, cancellation, and subscriber cleanup", %{
    manager: manager
  } do
    {:ok, pipeline_id} =
      Manager.create_pipeline(
        manager,
        """
        digraph {
          start [shape=Mdiamond]
          gate [shape=hexagon, prompt="Approve", human.timeout="10s"]
          done [shape=Msquare]
          start -> gate
          gate -> done [label="[A] Approve"]
        }
        """,
        %{},
        pipeline_id: "cancel-pipeline"
      )

    wait_until(fn ->
      match?({:ok, [_]}, Manager.pending_questions(manager, pipeline_id))
    end)

    assert {:ok, _dot} = Manager.pipeline_graph(manager, pipeline_id)
    assert {:ok, context} = Manager.pipeline_context(manager, pipeline_id)
    assert is_map(context)
    assert {:ok, checkpoint} = Manager.pipeline_checkpoint(manager, pipeline_id)
    assert is_nil(checkpoint) or checkpoint["current_node"] == "start"
    assert {:ok, events} = Manager.pipeline_events(manager, pipeline_id)
    assert is_list(events)
    assert {:error, :not_found} = Manager.submit_answer(manager, pipeline_id, "missing", "A")

    watcher =
      spawn(fn ->
        receive do
        after
          :infinity -> :ok
        end
      end)

    assert :ok = Manager.subscribe(manager, pipeline_id, watcher)
    assert :ok = Manager.subscribe(manager, pipeline_id, self())
    ref = Process.monitor(watcher)
    Process.exit(watcher, :kill)
    assert_receive {:DOWN, ^ref, :process, ^watcher, _}

    assert :ok = Manager.cancel(manager, pipeline_id)
    assert_receive {:pipeline_event, %{"type" => "PipelineFailed", "status" => "cancelled"}}
    assert {:ok, %{status: :cancelled}} = Manager.get_pipeline(manager, pipeline_id)
  end

  test "router returns 404s for unknown resources and filters unapproved opts", %{
    manager: manager
  } do
    opts = Router.init([])

    not_found_paths = [
      {:get, "/pipelines/missing"},
      {:get, "/pipelines/missing/graph"},
      {:get, "/pipelines/missing/questions"},
      {:get, "/pipelines/missing/checkpoint"},
      {:get, "/pipelines/missing/context"},
      {:get, "/pipelines/missing/events"},
      {:post, "/pipelines/missing/cancel"},
      {:post, "/pipelines/missing/questions/q1/answer"}
    ]

    Enum.each(not_found_paths, fn {method, path} ->
      conn = Router.call(conn(method, path), opts)
      assert conn.status == 404
    end)

    create_conn =
      conn(
        :post,
        "/pipelines",
        Jason.encode!(%{
          "dot_source" => "digraph { start [shape=Mdiamond] done [shape=Msquare] start -> done }",
          "opts" => %{"max_steps" => 5, "evil" => "ignored"}
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Router.call(opts)

    assert create_conn.status == 202
    %{"pipeline_id" => pipeline_id} = Jason.decode!(create_conn.resp_body)

    wait_until(fn ->
      case Manager.get_pipeline(manager, pipeline_id) do
        {:ok, %{status: status}} -> status in [:success, :fail]
        _ -> false
      end
    end)

    fallback_conn = Router.call(conn(:get, "/unknown"), opts)
    assert fallback_conn.status == 404
    assert Jason.decode!(fallback_conn.resp_body)["error"] == "not found"
  end

  test "manager reloads persisted runs and replays events after restart" do
    store_root = unique_store_root()
    manager_name = Module.concat(__MODULE__, ReloadManager)

    {:ok, manager} = Manager.start_link(name: manager_name, store_root: store_root)

    on_exit(fn ->
      if Process.whereis(manager_name), do: GenServer.stop(manager_name)
    end)

    {:ok, pipeline_id} =
      Manager.create_pipeline(
        manager,
        """
        digraph {
          start [shape=Mdiamond]
          done [shape=Msquare]
          start -> done
        }
        """,
        %{"ticket" => "R-1"},
        pipeline_id: "reloaded-pipeline",
        logs_root: unique_logs_root()
      )

    Manager.record_event(manager, pipeline_id, %{type: "PipelineHeartbeat", status: "running"})

    send(
      manager,
      {:pipeline_finished, pipeline_id,
       {:ok, %{status: :success, context: %{"run_id" => pipeline_id}, outcomes: %{}, history: []}}}
    )

    wait_until(fn ->
      match?({:ok, %{status: :success}}, Manager.get_pipeline(manager, pipeline_id))
    end)

    wait_until(fn ->
      case Manager.pipeline_events(manager, pipeline_id) do
        {:ok, [_ | _]} -> true
        _ -> false
      end
    end)

    assert {:ok, events_before} = Manager.pipeline_events(manager, pipeline_id)
    assert events_before != []

    GenServer.stop(manager)

    {:ok, reloaded} = Manager.start_link(name: manager_name, store_root: store_root)

    assert {:ok, %{status: :success, context: %{"run_id" => ^pipeline_id}}} =
             Manager.get_pipeline(reloaded, pipeline_id)

    assert {:ok, replayed} = Manager.replay_events(reloaded, pipeline_id, after_sequence: 1)
    assert Enum.all?(replayed, &(Map.fetch!(&1, "sequence") > 1))
  end

  test "router accepts `value` answers and successful cancel responses", _context do
    opts = Router.init([])

    create_conn =
      conn(
        :post,
        "/pipelines",
        Jason.encode!(%{
          "dot" => """
          digraph {
            start [shape=Mdiamond]
            gate [shape=hexagon, prompt="Approve", human.timeout="10s"]
            done [shape=Msquare]
            start -> gate
            gate -> done [label="[A] Approve"]
          }
          """,
          "opts" => "ignored"
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Router.call(opts)

    %{"pipeline_id" => pipeline_id} = Jason.decode!(create_conn.resp_body)

    wait_until(fn ->
      case Manager.pending_questions(AttractorEx.HTTP.Manager, pipeline_id) do
        {:ok, [_]} -> true
        _ -> false
      end
    end)

    answer_conn =
      conn(
        :post,
        "/pipelines/#{pipeline_id}/questions/gate/answer",
        Jason.encode!(%{"value" => "A"})
      )
      |> put_req_header("content-type", "application/json")
      |> Router.call(opts)

    assert answer_conn.status == 202

    cancel_conn =
      conn(:post, "/pipelines/#{pipeline_id}/cancel", Jason.encode!(%{}))
      |> put_req_header("content-type", "application/json")
      |> Router.call(opts)

    assert cancel_conn.status == 202
    assert Jason.decode!(cancel_conn.resp_body)["status"] == "cancelled"
  end

  test "http server wrapper starts and stops bandit", %{manager: manager, registry: registry} do
    {:ok, server_pid} =
      HTTP.start_server(manager: manager, registry: registry, port: 0, ip: {127, 0, 0, 1})

    assert Process.alive?(server_pid)
    assert :ok = HTTP.stop_server(server_pid)
    refute Process.alive?(server_pid)
  end

  test "http server wrapper tolerates already-started manager and registry", %{
    manager: manager,
    registry: registry
  } do
    {:ok, server_pid} =
      HTTP.start_server(manager: manager, registry: registry, port: 0, ip: {127, 0, 0, 1})

    assert Process.alive?(server_pid)
    assert :ok = HTTP.stop_server(server_pid)
  end

  test "http stop_server supports atom names" do
    stop_name = Module.concat(__MODULE__, StopManager)
    {:ok, pid} = GenServer.start_link(Manager, %{}, name: stop_name)
    assert Process.alive?(pid)
    assert :ok = HTTP.stop_server(stop_name)
    refute Process.alive?(pid)
  end

  defp wait_until(fun, attempts \\ 50)

  defp wait_until(_fun, 0), do: flunk("condition was not met in time")

  defp wait_until(fun, attempts) do
    if fun.() do
      :ok
    else
      receive do
      after
        10 -> wait_until(fun, attempts - 1)
      end
    end
  end

  defp unique_store_root do
    Path.join([
      "tmp",
      "http_manager_store_test",
      Integer.to_string(System.unique_integer([:positive]))
    ])
  end

  defp unique_logs_root do
    Path.join([
      "tmp",
      "http_manager_logs_test",
      Integer.to_string(System.unique_integer([:positive]))
    ])
  end
end
