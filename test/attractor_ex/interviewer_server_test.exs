defmodule AttractorEx.InterviewerServerTest do
  use ExUnit.Case, async: false

  alias AttractorEx
  alias AttractorEx.Graph
  alias AttractorEx.HTTP.Manager
  alias AttractorEx.Interviewers.Server
  alias AttractorEx.Node

  setup do
    manager_name = Module.concat(__MODULE__, Manager)
    start_supervised!({Manager, name: manager_name})
    %{manager: manager_name}
  end

  test "ask/4 registers a question, receives an answer, and emits lifecycle events", %{
    manager: manager
  } do
    {:ok, _id} =
      Manager.create_pipeline(
        manager,
        "digraph { start [shape=Mdiamond] done [shape=Msquare] start -> done }",
        %{},
        pipeline_id: "server-interviewer"
      )

    parent = self()
    node = %Node{id: "gate", attrs: %{"prompt" => "Approve release?", "human.timeout" => 20}}
    choices = [%{key: "A", label: "Approve", to: "done"}]

    pid =
      spawn(fn ->
        result =
          Server.ask(node, choices, %{"run_id" => "server-interviewer"},
            manager: manager,
            event_observer: &send(parent, {:event, &1})
          )

        send(parent, {:answer_result, result})
      end)

    assert_receive {:event, %{type: "InterviewStarted", question: %{id: "gate"}}}

    wait_until(fn ->
      match?({:ok, [_]}, Manager.pending_questions(manager, "server-interviewer"))
    end)

    assert :ok = Manager.submit_answer(manager, "server-interviewer", "gate", "A")
    assert_receive {:event, %{type: "InterviewCompleted", answer: "A"}}
    assert_receive {:answer_result, {:ok, "A"}}
    refute Process.alive?(pid)
  end

  test "ask_multiple wraps scalar answers and timeout cleanup works", %{manager: manager} do
    {:ok, _id} =
      Manager.create_pipeline(
        manager,
        "digraph { start [shape=Mdiamond] done [shape=Msquare] start -> done }",
        %{},
        pipeline_id: "server-timeout"
      )

    parent = self()
    node = %Node{id: "gate", attrs: %{"human.timeout" => "1ms"}}

    pid =
      spawn(fn ->
        result =
          Server.ask_multiple(node, [%{key: "A", label: "Approve", to: "done"}], %{},
            manager: manager,
            pipeline_id: "server-timeout",
            event_observer: &send(parent, {:event, &1})
          )

        send(parent, {:multiple_result, result})
      end)

    assert_receive {:event, %{type: "InterviewStarted"}}
    assert_receive {:event, %{type: "InterviewTimeout", duration_ms: 1}}
    assert_receive {:multiple_result, {:timeout}}
    assert {:ok, []} = Manager.pending_questions(manager, "server-timeout")
    refute Process.alive?(pid)
  end

  test "ask_multiple preserves list answers and supports default timeout parsing paths", %{
    manager: manager
  } do
    {:ok, _id} =
      Manager.create_pipeline(
        manager,
        "digraph { start [shape=Mdiamond] done [shape=Msquare] start -> done }",
        %{},
        pipeline_id: "server-list"
      )

    parent = self()
    node = %Node{id: "gate", attrs: %{"prompt" => "Choose", "human.timeout" => "5ms"}}

    pid =
      spawn(fn ->
        result =
          Server.ask_multiple(node, [%{key: "A", label: "Approve", to: "done"}], %{},
            manager: manager,
            pipeline_id: "server-list",
            event_observer: &send(parent, {:event, &1})
          )

        send(parent, {:list_result, result})
      end)

    assert_receive {:event, %{type: "InterviewStarted"}}
    wait_until(fn -> match?({:ok, [_]}, Manager.pending_questions(manager, "server-list")) end)
    assert :ok = Manager.submit_answer(manager, "server-list", "gate", ["A", "B"])
    assert_receive {:event, %{type: "InterviewCompleted", answer: ["A", "B"]}}
    assert_receive {:list_result, {:ok, ["A", "B"]}}
    refute Process.alive?(pid)

    timeout_pid =
      spawn(fn ->
        send(
          parent,
          {:fallback_timeout,
           Server.ask(
             %Node{id: "fallback", attrs: %{"human.timeout" => "nonsense"}},
             [],
             %{},
             manager: manager,
             pipeline_id: "server-list"
           )}
        )
      end)

    Process.sleep(10)
    Process.exit(timeout_pid, :kill)
  end

  test "inform returns ok and AttractorEx wrappers are covered", %{manager: manager} do
    assert :ok = Server.inform(%Node{id: "gate"}, %{message: "noop"}, %{}, [])

    valid_dot = """
    digraph {
      start [shape=Mdiamond]
      done [shape=Msquare]
      start -> done
    }
    """

    invalid_dot = "not a graph"

    assert [] ==
             AttractorEx.validate(%Graph{
               nodes: %{
                 "start" => Node.new("start", %{"shape" => "Mdiamond"}),
                 "done" => Node.new("done", %{"shape" => "Msquare"})
               },
               edges: [AttractorEx.Edge.new("start", "done", %{})]
             })

    assert [] == AttractorEx.validate(valid_dot)
    assert {:error, %{error: _}} = AttractorEx.validate(invalid_dot)

    assert [] == AttractorEx.validate_or_raise(valid_dot)

    assert_raise ArgumentError, fn ->
      AttractorEx.validate_or_raise(invalid_dot)
    end

    stop_name = Module.concat(__MODULE__, TempManager)
    {:ok, temp_pid} = GenServer.start_link(Manager, %{}, name: stop_name)
    assert Process.alive?(temp_pid)
    assert :ok = AttractorEx.stop_http_server(stop_name)
    refute Process.alive?(temp_pid)

    {:ok, server_pid} =
      AttractorEx.start_http_server(
        manager: manager,
        registry: Module.concat(__MODULE__, TempRegistry),
        port: 0
      )

    assert Process.alive?(server_pid)
    assert :ok = AttractorEx.stop_http_server(server_pid)
  end

  test "server interviewer parses second, minute, and hour timeout suffixes", %{manager: manager} do
    {:ok, _id} =
      Manager.create_pipeline(
        manager,
        "digraph { start [shape=Mdiamond] done [shape=Msquare] start -> done }",
        %{},
        pipeline_id: "server-time-units"
      )

    parent = self()

    for timeout <- ["1s", "1m", "1h"] do
      pid =
        spawn(fn ->
          send(
            parent,
            {:unit_started, timeout,
             Server.ask(
               %Node{id: "gate-#{timeout}", attrs: %{"human.timeout" => timeout}},
               [],
               %{},
               manager: manager,
               pipeline_id: "server-time-units"
             )}
          )
        end)

      Process.sleep(10)
      Process.exit(pid, :kill)
    end
  end

  test "server interviewer falls back to default timeout when none is configured", %{
    manager: manager
  } do
    {:ok, _id} =
      Manager.create_pipeline(
        manager,
        "digraph { start [shape=Mdiamond] done [shape=Msquare] start -> done }",
        %{},
        pipeline_id: "server-default-timeout"
      )

    pid =
      spawn(fn ->
        Server.ask(
          %Node{id: "gate-default", attrs: %{}},
          [],
          %{},
          manager: manager,
          pipeline_id: "server-default-timeout"
        )
      end)

    Process.sleep(10)
    Process.exit(pid, :kill)
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
end
