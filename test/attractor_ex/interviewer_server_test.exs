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

    assert_receive {:event,
                    %{
                      type: "InterviewStarted",
                      question: %{
                        id: "gate",
                        type: "CONFIRMATION",
                        multiple: false,
                        required: true,
                        metadata: %{
                          "choice_count" => 1,
                          "input_mode" => "confirmation",
                          "multiple" => false
                        },
                        options: [%{"key" => "A", "label" => "Approve", "to" => "done"}]
                      }
                    }}

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

  test "server interviewer infers yes/no question types and normalizes boolean answers", %{
    manager: manager
  } do
    {:ok, _id} =
      Manager.create_pipeline(
        manager,
        "digraph { start [shape=Mdiamond] done [shape=Msquare] start -> done }",
        %{},
        pipeline_id: "server-yes-no"
      )

    parent = self()

    node = %Node{id: "gate", attrs: %{"prompt" => "Ship it?", "human.timeout" => "5ms"}}

    choices = [
      %{key: "Y", label: "[Y] Yes", to: "done"},
      %{key: "N", label: "[N] No", to: "retry"}
    ]

    pid =
      spawn(fn ->
        result =
          Server.ask(node, choices, %{},
            manager: manager,
            pipeline_id: "server-yes-no",
            event_observer: &send(parent, {:event, &1})
          )

        send(parent, {:yes_no_result, result})
      end)

    assert_receive {:event, %{type: "InterviewStarted", question: %{id: "gate", type: "YES_NO"}}}
    wait_until(fn -> match?({:ok, [_]}, Manager.pending_questions(manager, "server-yes-no")) end)
    assert :ok = Manager.submit_answer(manager, "server-yes-no", "gate", true)
    assert_receive {:event, %{type: "InterviewCompleted", answer: "yes"}}
    assert_receive {:yes_no_result, {:ok, "yes"}}
    refute Process.alive?(pid)
  end

  test "server interviewer normalizes string yes/no and confirmation answers", %{manager: manager} do
    {:ok, _id} =
      Manager.create_pipeline(
        manager,
        "digraph { start [shape=Mdiamond] done [shape=Msquare] start -> done }",
        %{},
        pipeline_id: "server-string-normalization"
      )

    parent = self()

    yes_no_pid =
      spawn(fn ->
        result =
          Server.ask(
            %Node{id: "yes-no", attrs: %{"prompt" => "Ship?", "human.timeout" => "1s"}},
            [
              %{key: "Y", label: "[Y] Yes", to: "done"},
              %{key: "N", label: "[N] No", to: "retry"}
            ],
            %{},
            manager: manager,
            pipeline_id: "server-string-normalization"
          )

        send(parent, {:yes_no_string_result, result})
      end)

    wait_until(fn ->
      match?(
        {:ok, [%{id: "yes-no"}]},
        Manager.pending_questions(manager, "server-string-normalization")
      )
    end)

    assert :ok =
             Manager.submit_answer(
               manager,
               "server-string-normalization",
               "yes-no",
               %{"answer" => " approve "}
             )

    assert_receive {:yes_no_string_result, {:ok, "yes"}}
    refute Process.alive?(yes_no_pid)

    confirmation_pid =
      spawn(fn ->
        result =
          Server.ask(
            %Node{id: "confirm", attrs: %{"prompt" => "Confirm?", "human.timeout" => "1s"}},
            [%{key: "C", label: "[C] Confirm", to: "done"}],
            %{},
            manager: manager,
            pipeline_id: "server-string-normalization"
          )

        send(parent, {:confirmation_string_result, result})
      end)

    wait_until(fn ->
      case Manager.pending_questions(manager, "server-string-normalization") do
        {:ok, questions} -> Enum.any?(questions, &(&1.id == "confirm"))
        _ -> false
      end
    end)

    assert :ok =
             Manager.submit_answer(
               manager,
               "server-string-normalization",
               "confirm",
               %{"value" => " cancel "}
             )

    assert_receive {:confirmation_string_result, {:ok, "cancel"}}
    refute Process.alive?(confirmation_pid)
  end

  test "server interviewer exposes freeform questions and normalizes map answers", %{
    manager: manager
  } do
    {:ok, _id} =
      Manager.create_pipeline(
        manager,
        "digraph { start [shape=Mdiamond] done [shape=Msquare] start -> done }",
        %{},
        pipeline_id: "server-freeform"
      )

    parent = self()
    node = %Node{id: "gate", attrs: %{"prompt" => "Explain", "human.timeout" => "5ms"}}

    pid =
      spawn(fn ->
        result =
          Server.ask(node, [], %{},
            manager: manager,
            pipeline_id: "server-freeform",
            event_observer: &send(parent, {:event, &1})
          )

        send(parent, {:freeform_result, result})
      end)

    assert_receive {:event,
                    %{type: "InterviewStarted", question: %{id: "gate", type: "FREEFORM"}}}

    wait_until(fn -> match?({:ok, [_]}, Manager.pending_questions(manager, "server-freeform")) end)

    assert :ok =
             Manager.submit_answer(manager, "server-freeform", "gate", %{
               "answer" => "  details  "
             })

    assert_receive {:event, %{type: "InterviewCompleted", answer: "details"}}
    assert_receive {:freeform_result, {:ok, "details"}}
    refute Process.alive?(pid)
  end

  test "server interviewer respects human.multiple and normalizes structured list answers", %{
    manager: manager
  } do
    {:ok, _id} =
      Manager.create_pipeline(
        manager,
        "digraph { start [shape=Mdiamond] done [shape=Msquare] start -> done }",
        %{},
        pipeline_id: "server-multiple"
      )

    parent = self()

    node = %Node{
      id: "gate",
      attrs: %{"prompt" => "Choose", "human.timeout" => "5ms", "human.multiple" => "yes"}
    }

    choices = [
      %{key: "A", label: "[A] Approve", to: "done"},
      %{key: "B", label: "[B] Block", to: "retry"}
    ]

    pid =
      spawn(fn ->
        result =
          Server.ask_multiple(node, choices, %{},
            manager: manager,
            pipeline_id: "server-multiple",
            event_observer: &send(parent, {:event, &1})
          )

        send(parent, {:multiple_choice_result, result})
      end)

    assert_receive {:event,
                    %{type: "InterviewStarted", question: %{id: "gate", type: "MULTIPLE_CHOICE"}}}

    wait_until(fn -> match?({:ok, [_]}, Manager.pending_questions(manager, "server-multiple")) end)

    assert :ok =
             Manager.submit_answer(manager, "server-multiple", "gate", [
               %{"key" => "A"},
               %{"value" => " B "}
             ])

    assert_receive {:event, %{type: "InterviewCompleted", answer: ["A", "B"]}}
    assert_receive {:multiple_choice_result, {:ok, ["A", "B"]}}
    refute Process.alive?(pid)
  end

  test "server interviewer exposes human.required and human.input metadata overrides", %{
    manager: manager
  } do
    {:ok, _id} =
      Manager.create_pipeline(
        manager,
        "digraph { start [shape=Mdiamond] done [shape=Msquare] start -> done }",
        %{},
        pipeline_id: "server-metadata-overrides"
      )

    parent = self()

    node = %Node{
      id: "gate",
      attrs: %{
        "prompt" => "Explain why",
        "human.timeout" => "1s",
        "human.required" => "false",
        "human.input" => "textarea"
      }
    }

    pid =
      spawn(fn ->
        result =
          Server.ask(node, [], %{},
            manager: manager,
            pipeline_id: "server-metadata-overrides",
            event_observer: &send(parent, {:event, &1})
          )

        send(parent, {:metadata_override_result, result})
      end)

    assert_receive {:event,
                    %{
                      type: "InterviewStarted",
                      question: %{
                        id: "gate",
                        type: "FREEFORM",
                        required: false,
                        metadata: %{"input_mode" => "textarea", "required" => false}
                      }
                    }}

    wait_until(fn ->
      match?(
        {:ok, [%{id: "gate"}]},
        Manager.pending_questions(manager, "server-metadata-overrides")
      )
    end)

    assert :ok =
             Manager.submit_answer(
               manager,
               "server-metadata-overrides",
               "gate",
               %{"answer" => "details"}
             )

    assert_receive {:metadata_override_result, {:ok, "details"}}
    refute Process.alive?(pid)
  end

  test "server interviewer accepts nested structured multiple answers", %{manager: manager} do
    {:ok, _id} =
      Manager.create_pipeline(
        manager,
        "digraph { start [shape=Mdiamond] done [shape=Msquare] start -> done }",
        %{},
        pipeline_id: "server-nested-multiple"
      )

    parent = self()

    pid =
      spawn(fn ->
        result =
          Server.ask_multiple(
            %Node{
              id: "gate",
              attrs: %{"prompt" => "Choose", "human.timeout" => "1s", "human.multiple" => true}
            },
            [
              %{key: "A", label: "[A] Approve", to: "done"},
              %{key: "B", label: "[B] Block", to: "retry"}
            ],
            %{},
            manager: manager,
            pipeline_id: "server-nested-multiple"
          )

        send(parent, {:nested_multiple_result, result})
      end)

    wait_until(fn ->
      match?({:ok, [%{id: "gate"}]}, Manager.pending_questions(manager, "server-nested-multiple"))
    end)

    assert :ok =
             Manager.submit_answer(manager, "server-nested-multiple", "gate", %{
               "selected" => [%{"key" => "A"}, %{"answer" => " B "}]
             })

    assert_receive {:nested_multiple_result, {:ok, ["A", "B"]}}
    refute Process.alive?(pid)
  end

  test "server interviewer normalizes false confirmation answers without an observer", %{
    manager: manager
  } do
    {:ok, _id} =
      Manager.create_pipeline(
        manager,
        "digraph { start [shape=Mdiamond] done [shape=Msquare] start -> done }",
        %{},
        pipeline_id: "server-confirmation-cancel"
      )

    parent = self()
    node = %Node{id: "gate", attrs: %{"prompt" => "Confirm?", "human.timeout" => "1s"}}
    choices = [%{key: "C", label: "[C] Confirm", to: "done"}]

    pid =
      spawn(fn ->
        send(
          parent,
          {:cancel_result,
           Server.ask(node, choices, %{},
             manager: manager,
             pipeline_id: "server-confirmation-cancel"
           )}
        )
      end)

    wait_until(fn ->
      match?({:ok, [_]}, Manager.pending_questions(manager, "server-confirmation-cancel"))
    end)

    assert :ok = Manager.submit_answer(manager, "server-confirmation-cancel", "gate", false)
    assert_receive {:cancel_result, {:ok, "cancel"}}
    refute Process.alive?(pid)
  end

  test "server interviewer treats boolean human.multiple as multiple choice", %{
    manager: manager
  } do
    {:ok, _id} =
      Manager.create_pipeline(
        manager,
        "digraph { start [shape=Mdiamond] done [shape=Msquare] start -> done }",
        %{},
        pipeline_id: "server-bool-multiple"
      )

    parent = self()

    node = %Node{
      id: "gate",
      attrs: %{"prompt" => "Choose", "human.timeout" => "1s", "human.multiple" => true}
    }

    choices = [%{key: "A", label: "[A] Approve", to: "done"}]

    pid =
      spawn(fn ->
        result =
          Server.ask_multiple(node, choices, %{},
            manager: manager,
            pipeline_id: "server-bool-multiple",
            event_observer: &send(parent, {:event, &1})
          )

        send(parent, {:bool_multiple_result, result})
      end)

    assert_receive {:event,
                    %{type: "InterviewStarted", question: %{id: "gate", type: "MULTIPLE_CHOICE"}}}

    wait_until(fn ->
      match?({:ok, [_]}, Manager.pending_questions(manager, "server-bool-multiple"))
    end)

    assert :ok =
             Manager.submit_answer(manager, "server-bool-multiple", "gate", [
               %{"answer" => "A"},
               7
             ])

    assert_receive {:event, %{type: "InterviewCompleted", answer: ["A", 7]}}
    assert_receive {:bool_multiple_result, {:ok, ["A", 7]}}
    refute Process.alive?(pid)
  end

  test "server interviewer wraps scalar ask_multiple answers and accepts second-only timeouts", %{
    manager: manager
  } do
    {:ok, _id} =
      Manager.create_pipeline(
        manager,
        "digraph { start [shape=Mdiamond] done [shape=Msquare] start -> done }",
        %{},
        pipeline_id: "server-scalar-multiple"
      )

    parent = self()

    node = %Node{id: "gate", attrs: %{"prompt" => "Choose", "human.timeout" => "5"}}

    choices = [
      %{key: "A", label: "[A] Alpha", to: "alpha"},
      %{key: "B", label: "[B] Beta", to: "beta"},
      %{key: "C", label: "[C] Gamma", to: "gamma"}
    ]

    pid =
      spawn(fn ->
        result =
          Server.ask_multiple(node, choices, %{},
            manager: manager,
            pipeline_id: "server-scalar-multiple",
            event_observer: &send(parent, {:event, &1})
          )

        send(parent, {:scalar_multiple_result, result})
      end)

    assert_receive {:event,
                    %{type: "InterviewStarted", question: %{id: "gate", type: "MULTIPLE_CHOICE"}}}

    wait_until(fn ->
      match?({:ok, [_]}, Manager.pending_questions(manager, "server-scalar-multiple"))
    end)

    assert :ok = Manager.submit_answer(manager, "server-scalar-multiple", "gate", %{key: "A"})
    assert_receive {:event, %{type: "InterviewCompleted", answer: "A"}}
    assert_receive {:scalar_multiple_result, {:ok, ["A"]}}
    refute Process.alive?(pid)
  end

  test "server interviewer tolerates nil choice fields while inferring non-yes-no multiple choice",
       %{
         manager: manager
       } do
    {:ok, _id} =
      Manager.create_pipeline(
        manager,
        "digraph { start [shape=Mdiamond] done [shape=Msquare] start -> done }",
        %{},
        pipeline_id: "server-nil-choices"
      )

    parent = self()
    node = %Node{id: "gate", attrs: %{"prompt" => "Choose", "human.timeout" => "1s"}}

    choices = [
      %{key: nil, label: nil, to: "alpha"},
      %{key: "B", label: "[B] Beta", to: "beta"}
    ]

    pid =
      spawn(fn ->
        result =
          Server.ask(node, choices, %{},
            manager: manager,
            pipeline_id: "server-nil-choices",
            event_observer: &send(parent, {:event, &1})
          )

        send(parent, {:nil_choice_result, result})
      end)

    assert_receive {:event,
                    %{type: "InterviewStarted", question: %{id: "gate", type: "MULTIPLE_CHOICE"}}}

    wait_until(fn ->
      match?({:ok, [_]}, Manager.pending_questions(manager, "server-nil-choices"))
    end)

    assert :ok = Manager.submit_answer(manager, "server-nil-choices", "gate", "B")
    assert_receive {:event, %{type: "InterviewCompleted", answer: "B"}}
    assert_receive {:nil_choice_result, {:ok, "B"}}
    refute Process.alive?(pid)
  end

  test "server interviewer defaults to multiple choice for non-boolean two-option prompts", %{
    manager: manager
  } do
    {:ok, _id} =
      Manager.create_pipeline(
        manager,
        "digraph { start [shape=Mdiamond] done [shape=Msquare] start -> done }",
        %{},
        pipeline_id: "server-default-multiple"
      )

    parent = self()

    node = %Node{id: "gate", attrs: %{"prompt" => "Pick", "human.timeout" => "1s"}}

    choices = [
      %{key: "A", label: "[A] Alpha", to: "alpha"},
      %{key: "B", label: "[B] Beta", to: "beta"}
    ]

    pid =
      spawn(fn ->
        result =
          Server.ask(node, choices, %{},
            manager: manager,
            pipeline_id: "server-default-multiple",
            event_observer: &send(parent, {:event, &1})
          )

        send(parent, {:default_multiple_result, result})
      end)

    assert_receive {:event,
                    %{type: "InterviewStarted", question: %{id: "gate", type: "MULTIPLE_CHOICE"}}}

    wait_until(fn ->
      match?({:ok, [_]}, Manager.pending_questions(manager, "server-default-multiple"))
    end)

    assert :ok =
             Manager.submit_answer(manager, "server-default-multiple", "gate", %{answer: " A "})

    assert_receive {:event, %{type: "InterviewCompleted", answer: "A"}}
    assert_receive {:default_multiple_result, {:ok, "A"}}
    refute Process.alive?(pid)
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

  test "server interviewer parses day timeout suffixes", %{manager: manager} do
    {:ok, _id} =
      Manager.create_pipeline(
        manager,
        "digraph { start [shape=Mdiamond] done [shape=Msquare] start -> done }",
        %{},
        pipeline_id: "server-day-time-unit"
      )

    pid =
      spawn(fn ->
        Server.ask(
          %Node{id: "gate-1d", attrs: %{"human.timeout" => "1d"}},
          [],
          %{},
          manager: manager,
          pipeline_id: "server-day-time-unit"
        )
      end)

    Process.sleep(10)
    Process.exit(pid, :kill)
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
