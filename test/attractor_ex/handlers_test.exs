defmodule AttractorEx.HandlersTest do
  use ExUnit.Case, async: true

  alias AttractorEx.LLM.Client
  alias AttractorEx.{Edge, Graph, Node, Outcome}

  describe "spec: handler contracts" do
    test "start handler is a no-op success" do
      node = Node.new("start", %{"shape" => "Mdiamond"})

      outcome =
        AttractorEx.Handlers.Start.execute(node, %{}, %Graph{}, unique_stage_dir("start"), [])

      assert outcome.status == :success
    end

    test "exit handler is a no-op success" do
      node = Node.new("done", %{"shape" => "Msquare"})

      outcome =
        AttractorEx.Handlers.Exit.execute(node, %{}, %Graph{}, unique_stage_dir("exit"), [])

      assert outcome.status == :success
    end

    test "conditional handler is a no-op success with note" do
      node = Node.new("gate", %{"shape" => "diamond"})

      outcome =
        AttractorEx.Handlers.Conditional.execute(
          node,
          %{},
          %Graph{},
          unique_stage_dir("conditional"),
          []
        )

      assert outcome.status == :success
      assert outcome.notes =~ "gate"
    end

    test "codergen expands $goal and writes prompt/response artifacts" do
      node = Node.new("plan", %{"shape" => "box", "prompt" => "Plan for $goal"})
      graph = %{attrs: %{"goal" => "ship feature"}}
      stage_dir = unique_stage_dir("codergen")

      outcome =
        AttractorEx.Handlers.Codergen.execute(node, %{}, graph, stage_dir,
          codergen_backend: AttractorExTest.EchoBackend
        )

      assert outcome.status == :success
      assert File.read!(Path.join(stage_dir, "prompt.md")) == "Plan for ship feature"
      assert File.read!(Path.join(stage_dir, "response.md")) =~ "echo:plan:Plan for ship feature"
      assert File.exists?(Path.join(stage_dir, "status.json"))
    end

    test "codergen fails when prompt and label are missing" do
      node = Node.new("plan", %{"shape" => "box"})
      graph = %{attrs: %{"goal" => "x"}}

      outcome =
        AttractorEx.Handlers.Codergen.execute(
          node,
          %{},
          graph,
          unique_stage_dir("codergen_missing"),
          []
        )

      assert outcome.status == :fail
    end

    test "codergen uses unified llm client when provided" do
      node =
        Node.new("plan", %{
          "shape" => "box",
          "prompt" => "Plan for $goal",
          "llm_model" => "gpt-5.2",
          "llm_provider" => "openai",
          "reasoning_effort" => "medium",
          "max_tokens" => "64",
          "temperature" => "0.2"
        })

      graph = %{attrs: %{"goal" => "ship feature"}}
      stage_dir = unique_stage_dir("codergen_llm_client")

      llm_client = %Client{
        providers: %{"openai" => AttractorExTest.LLMAdapter},
        default_provider: "openai"
      }

      outcome =
        AttractorEx.Handlers.Codergen.execute(node, %{}, graph, stage_dir, llm_client: llm_client)

      assert outcome.status == :success
      assert File.read!(Path.join(stage_dir, "response.md")) =~ "model=gpt-5.2"
      assert get_in(outcome.context_updates, ["llm", "provider"]) == "openai"
      assert get_in(outcome.context_updates, ["llm", "usage", "reasoning_tokens"]) == 2
    end

    test "codergen llm client requires model when backend path is selected" do
      node =
        Node.new("plan", %{
          "shape" => "box",
          "prompt" => "Plan for $goal",
          "llm_provider" => "openai"
        })

      graph = %{attrs: %{"goal" => "ship feature"}}
      stage_dir = unique_stage_dir("codergen_llm_model_required")

      llm_client = %Client{
        providers: %{"openai" => AttractorExTest.LLMAdapter},
        default_provider: "openai"
      }

      outcome =
        AttractorEx.Handlers.Codergen.execute(node, %{}, graph, stage_dir, llm_client: llm_client)

      assert outcome.status == :fail
      assert outcome.failure_reason =~ "llm_model"
    end

    test "codergen records resolved provider from llm client default" do
      node = Node.new("plan", %{"shape" => "box", "prompt" => "Plan", "llm_model" => "gpt-5.2"})
      graph = %{attrs: %{}}
      stage_dir = unique_stage_dir("codergen_llm_default_provider")

      llm_client = %Client{
        providers: %{"openai" => AttractorExTest.LLMAdapter},
        default_provider: "openai"
      }

      outcome =
        AttractorEx.Handlers.Codergen.execute(node, %{}, graph, stage_dir, llm_client: llm_client)

      assert outcome.status == :success
      assert get_in(outcome.context_updates, ["llm", "provider"]) == "openai"
    end

    test "wait_for_human returns retry when no answer is provided" do
      node = Node.new("gate", %{"type" => "wait.human"})
      graph = %Graph{edges: [Edge.new("gate", "done", %{"label" => "[Y] Continue"})]}

      outcome =
        AttractorEx.Handlers.WaitForHuman.execute(
          node,
          %{},
          graph,
          unique_stage_dir("human_retry"),
          []
        )

      assert outcome.status == :retry
    end

    test "wait_for_human picks answer and sets suggested_next_ids/context updates" do
      node = Node.new("gate", %{"type" => "wait.human"})
      graph = %Graph{edges: [Edge.new("gate", "ship_it", %{"label" => "[A] Approve"})]}

      outcome =
        AttractorEx.Handlers.WaitForHuman.execute(
          node,
          %{"human" => %{"answers" => %{"gate" => "A"}}},
          graph,
          unique_stage_dir("human_ok"),
          []
        )

      assert outcome.status == :success
      assert outcome.suggested_next_ids == ["ship_it"]
      assert get_in(outcome.context_updates, ["human", "gate", "selected"]) == "A"
      assert get_in(outcome.context_updates, ["human", "gate", "label"]) == "[A] Approve"
    end

    test "wait_for_human handles timeout with default choice" do
      node = Node.new("gate", %{"type" => "wait.human", "human.default_choice" => "fixes"})

      graph = %Graph{
        edges: [
          Edge.new("gate", "ship_it", %{"label" => "[A] Approve"}),
          Edge.new("gate", "fixes", %{"label" => "[F] Fix"})
        ]
      }

      outcome =
        AttractorEx.Handlers.WaitForHuman.execute(
          node,
          %{"human" => %{"answers" => %{"gate" => "timeout"}}},
          graph,
          unique_stage_dir("human_timeout"),
          []
        )

      assert outcome.status == :success
      assert outcome.suggested_next_ids == ["fixes"]
    end

    test "wait_for_human retries on timeout without default choice" do
      node = Node.new("gate", %{"type" => "wait.human"})
      graph = %Graph{edges: [Edge.new("gate", "done", %{"label" => "[Y] Continue"})]}

      outcome =
        AttractorEx.Handlers.WaitForHuman.execute(
          node,
          %{"human" => %{"answers" => %{"gate" => "timed_out"}}},
          graph,
          unique_stage_dir("human_timeout_no_default"),
          []
        )

      assert outcome.status == :retry
      assert outcome.failure_reason =~ "no default"
    end

    test "wait_for_human supports accelerator variants and fallback selection" do
      node = Node.new("gate", %{"type" => "wait.human"})

      graph = %Graph{
        edges: [
          Edge.new("gate", "approved", %{"label" => "Y) Yes"}),
          Edge.new("gate", "rejected", %{"label" => "N - No"})
        ]
      }

      outcome =
        AttractorEx.Handlers.WaitForHuman.execute(
          node,
          %{"human" => %{"answers" => %{"gate" => "unknown-answer"}}},
          graph,
          unique_stage_dir("human_accelerators"),
          []
        )

      assert outcome.status == :success
      assert outcome.suggested_next_ids == ["approved"]
    end

    test "wait_for_human supports legacy context.human.<node>.answer path" do
      node = Node.new("gate", %{"type" => "wait.human"})
      graph = %Graph{edges: [Edge.new("gate", "ship_it", %{"label" => "[S] Ship"})]}

      outcome =
        AttractorEx.Handlers.WaitForHuman.execute(
          node,
          %{"human" => %{"gate" => %{"answer" => "S"}}},
          graph,
          unique_stage_dir("human_legacy_answer"),
          []
        )

      assert outcome.status == :success
      assert outcome.suggested_next_ids == ["ship_it"]
    end

    test "wait_for_human handles non-graph argument by failing on empty choices" do
      node = Node.new("gate", %{"type" => "wait.human"})

      outcome =
        AttractorEx.Handlers.WaitForHuman.execute(
          node,
          %{},
          %{},
          unique_stage_dir("human_non_graph"),
          []
        )

      assert outcome.status == :fail
    end

    test "wait_for_human fails when interaction is skipped" do
      node = Node.new("gate", %{"type" => "wait.human"})
      graph = %Graph{edges: [Edge.new("gate", "done", %{})]}

      outcome =
        AttractorEx.Handlers.WaitForHuman.execute(
          node,
          %{"human" => %{"answers" => %{"gate" => "skipped"}}},
          graph,
          unique_stage_dir("human_skip"),
          []
        )

      assert outcome.status == :fail
      assert outcome.failure_reason =~ "skipped"
    end

    test "wait_for_human fails when node has no outgoing edges" do
      node = Node.new("gate", %{"type" => "wait.human"})

      outcome =
        AttractorEx.Handlers.WaitForHuman.execute(
          node,
          %{},
          %Graph{},
          unique_stage_dir("human_empty"),
          []
        )

      assert outcome.status == :fail
      assert outcome.failure_reason =~ "No outgoing edges"
    end

    test "wait_for_human supports auto_approve interviewer" do
      node = Node.new("gate", %{"type" => "wait.human"})
      graph = %Graph{edges: [Edge.new("gate", "ship_it", %{"label" => "[S] Ship"})]}

      outcome =
        AttractorEx.Handlers.WaitForHuman.execute(
          node,
          %{},
          graph,
          unique_stage_dir("human_auto_approve"),
          interviewer: :auto_approve
        )

      assert outcome.status == :success
      assert outcome.suggested_next_ids == ["ship_it"]
    end

    test "wait_for_human supports callback interviewer" do
      node = Node.new("gate", %{"type" => "wait.human"})

      graph = %Graph{
        edges: [
          Edge.new("gate", "ship_it", %{"label" => "[S] Ship"}),
          Edge.new("gate", "fixes", %{"label" => "[F] Fix"})
        ]
      }

      callback = fn _node, _choices, _ctx -> {:ok, "F"} end

      outcome =
        AttractorEx.Handlers.WaitForHuman.execute(
          node,
          %{},
          graph,
          unique_stage_dir("human_callback"),
          interviewer: :callback,
          callback: callback
        )

      assert outcome.status == :success
      assert outcome.suggested_next_ids == ["fixes"]
    end

    test "wait_for_human supports queue interviewer with agent queue" do
      node = Node.new("gate", %{"type" => "wait.human"})
      graph = %Graph{edges: [Edge.new("gate", "ship_it", %{"label" => "[S] Ship"})]}
      queue = start_supervised!({Agent, fn -> ["S"] end})

      outcome =
        AttractorEx.Handlers.WaitForHuman.execute(
          node,
          %{},
          graph,
          unique_stage_dir("human_queue"),
          interviewer: :queue,
          queue: queue
        )

      assert outcome.status == :success
      assert outcome.suggested_next_ids == ["ship_it"]
      assert Agent.get(queue, & &1) == []
    end

    test "wait_for_human maps interviewer timeout to retry without default" do
      node = Node.new("gate", %{"type" => "wait.human"})
      graph = %Graph{edges: [Edge.new("gate", "ship_it", %{"label" => "[S] Ship"})]}
      callback = fn _node, _choices, _ctx -> :timeout end

      outcome =
        AttractorEx.Handlers.WaitForHuman.execute(
          node,
          %{},
          graph,
          unique_stage_dir("human_callback_timeout"),
          interviewer: :callback,
          callback: callback
        )

      assert outcome.status == :retry
      assert outcome.failure_reason =~ "timeout"
    end

    test "wait_for_human maps interviewer skip to failure" do
      node = Node.new("gate", %{"type" => "wait.human"})
      graph = %Graph{edges: [Edge.new("gate", "ship_it", %{"label" => "[S] Ship"})]}
      callback = fn _node, _choices, _ctx -> {:skip} end

      outcome =
        AttractorEx.Handlers.WaitForHuman.execute(
          node,
          %{},
          graph,
          unique_stage_dir("human_callback_skip"),
          interviewer: :callback,
          callback: callback
        )

      assert outcome.status == :fail
      assert outcome.failure_reason =~ "skipped"
    end

    test "wait_for_human returns interviewer error for invalid interviewer config" do
      node = Node.new("gate", %{"type" => "wait.human"})
      graph = %Graph{edges: [Edge.new("gate", "ship_it", %{"label" => "[S] Ship"})]}

      invalid_type =
        AttractorEx.Handlers.WaitForHuman.execute(
          node,
          %{},
          graph,
          unique_stage_dir("human_invalid_interviewer_type"),
          interviewer: "bad"
        )

      missing_ask =
        AttractorEx.Handlers.WaitForHuman.execute(
          node,
          %{},
          graph,
          unique_stage_dir("human_invalid_interviewer_module"),
          interviewer: AttractorEx.Graph
        )

      missing_callback =
        AttractorEx.Handlers.WaitForHuman.execute(
          node,
          %{},
          graph,
          unique_stage_dir("human_invalid_callback"),
          interviewer: :callback
        )

      assert invalid_type.status == :retry
      assert invalid_type.failure_reason =~ "invalid interviewer"
      assert missing_ask.status == :retry
      assert missing_ask.failure_reason =~ "does not implement ask/4"
      assert missing_callback.status == :retry
      assert missing_callback.failure_reason =~ "requires :callback function"
    end

    test "wait_for_human treats nil interviewer response as missing answer" do
      node = Node.new("gate", %{"type" => "wait.human"})
      graph = %Graph{edges: [Edge.new("gate", "ship_it", %{"label" => "[S] Ship"})]}
      callback = fn _node, _choices, _ctx -> nil end

      outcome =
        AttractorEx.Handlers.WaitForHuman.execute(
          node,
          %{},
          graph,
          unique_stage_dir("human_callback_nil"),
          interviewer: :callback,
          callback: callback
        )

      assert outcome.status == :retry
      assert outcome.failure_reason =~ "requires answer"
    end

    test "tool handler fails when command is missing" do
      node = Node.new("tool", %{"shape" => "parallelogram"})

      outcome =
        AttractorEx.Handlers.Tool.execute(node, %{}, %{}, unique_stage_dir("tool_missing"), [])

      assert outcome.status == :fail
    end

    test "tool handler executes configured command" do
      node = Node.new("tool", %{"shape" => "parallelogram", "tool_command" => "echo ok"})
      outcome = AttractorEx.Handlers.Tool.execute(node, %{}, %{}, unique_stage_dir("tool_ok"), [])

      assert %Outcome{status: :success} = outcome
      assert get_in(outcome.context_updates, ["tools", "tool"]) =~ "ok"
      assert get_in(outcome.context_updates, ["tool.output"]) =~ "ok"
    end

    test "tool handler returns fail on non-zero exit status" do
      cmd =
        case :os.type() do
          {:win32, _} -> "cmd /c exit /b 7"
          _ -> "sh -lc 'exit 7'"
        end

      node = Node.new("tool_fail", %{"shape" => "parallelogram", "tool_command" => cmd})

      outcome =
        AttractorEx.Handlers.Tool.execute(node, %{}, %{}, unique_stage_dir("tool_fail"), [])

      assert outcome.status == :fail
      assert outcome.failure_reason =~ "Tool command failed"
    end

    test "parallel handler executes branch runner and records parallel.results" do
      node =
        Node.new("fork", %{
          "shape" => "component",
          "join_policy" => "wait_all",
          "max_parallel" => 2
        })

      graph = %Graph{
        edges: [
          Edge.new("fork", "a", %{"score" => 0.9}),
          Edge.new("fork", "b", %{"score" => 0.2})
        ]
      }

      runner = fn to, _ctx, _graph, _opts ->
        case to do
          "a" -> Outcome.success(%{}, "ok")
          "b" -> Outcome.partial_success(%{}, "partial")
        end
      end

      outcome =
        AttractorEx.Handlers.Parallel.execute(
          node,
          %{},
          graph,
          unique_stage_dir("parallel"),
          parallel_branch_runner: runner
        )

      assert outcome.status == :success or outcome.status == :partial_success
      assert is_list(get_in(outcome.context_updates, ["parallel.results"]))
      assert Enum.count(get_in(outcome.context_updates, ["parallel.results"])) == 2
    end

    test "parallel handler fails when no outgoing branches exist" do
      node = Node.new("fork", %{"shape" => "component"})

      outcome =
        AttractorEx.Handlers.Parallel.execute(
          node,
          %{},
          %Graph{},
          unique_stage_dir("parallel_empty"),
          []
        )

      assert outcome.status == :fail
      assert outcome.failure_reason =~ "No outgoing branches"
    end

    test "parallel handler supports first_success policy with all failures" do
      node = Node.new("fork", %{"shape" => "component", "join_policy" => "first_success"})
      graph = %Graph{edges: [Edge.new("fork", "a", %{}), Edge.new("fork", "b", %{})]}
      runner = fn _to, _ctx, _graph, _opts -> Outcome.fail("boom") end

      outcome =
        AttractorEx.Handlers.Parallel.execute(
          node,
          %{},
          graph,
          unique_stage_dir("parallel_first_success_fail"),
          parallel_branch_runner: runner
        )

      assert outcome.status == :fail
    end

    test "parallel handler supports k_of_n policy" do
      node = Node.new("fork", %{"shape" => "component", "join_policy" => "k_of_n", "k" => "2"})

      graph = %Graph{
        edges: [
          Edge.new("fork", "a", %{}),
          Edge.new("fork", "b", %{}),
          Edge.new("fork", "c", %{})
        ]
      }

      runner = fn to, _ctx, _graph, _opts ->
        if to in ["a", "b"], do: Outcome.success(), else: Outcome.fail("c failed")
      end

      outcome =
        AttractorEx.Handlers.Parallel.execute(
          node,
          %{},
          graph,
          unique_stage_dir("parallel_k_of_n"),
          parallel_branch_runner: runner
        )

      assert outcome.status == :success
    end

    test "parallel handler supports quorum policy and float parsing fallback" do
      node =
        Node.new("fork", %{
          "shape" => "component",
          "join_policy" => "quorum",
          "quorum_ratio" => "0.66",
          "max_parallel" => "not-a-number"
        })

      graph = %Graph{
        edges: [
          Edge.new("fork", "a", %{}),
          Edge.new("fork", "b", %{}),
          Edge.new("fork", "c", %{})
        ]
      }

      runner = fn to, _ctx, _graph, _opts ->
        if to == "c", do: Outcome.fail("no"), else: Outcome.success()
      end

      outcome =
        AttractorEx.Handlers.Parallel.execute(
          node,
          %{},
          graph,
          unique_stage_dir("parallel_quorum"),
          parallel_branch_runner: runner
        )

      assert outcome.status == :success
    end

    test "parallel handler returns partial_success for wait_all when any branch fails" do
      node = Node.new("fork", %{"shape" => "component", "join_policy" => "wait_all"})
      graph = %Graph{edges: [Edge.new("fork", "a", %{}), Edge.new("fork", "b", %{})]}

      runner = fn to, _ctx, _graph, _opts ->
        if to == "a", do: Outcome.success(), else: Outcome.fail("bad")
      end

      outcome =
        AttractorEx.Handlers.Parallel.execute(
          node,
          %{},
          graph,
          unique_stage_dir("parallel_wait_all_partial"),
          parallel_branch_runner: runner
        )

      assert outcome.status == :partial_success
    end

    test "parallel handler normalizes non-outcome branch results and default runner path" do
      node = Node.new("fork", %{"shape" => "component"})

      graph = %Graph{
        edges: [Edge.new("fork", "a", %{"score" => 1}), Edge.new("fork", "b", %{"score" => %{}})]
      }

      custom =
        AttractorEx.Handlers.Parallel.execute(
          node,
          %{},
          graph,
          unique_stage_dir("parallel_non_outcome"),
          parallel_branch_runner: fn _to, _ctx, _graph, _opts -> :ok end
        )

      assert custom.status == :success
      assert Enum.all?(custom.context_updates["parallel.results"], &is_map/1)

      with_default =
        AttractorEx.Handlers.Parallel.execute(
          node,
          %{},
          graph,
          unique_stage_dir("parallel_default_runner"),
          []
        )

      assert with_default.status == :success
    end

    test "parallel handler handles non-integer max_parallel fallback" do
      node = Node.new("fork", %{"shape" => "component", "max_parallel" => %{}})
      graph = %Graph{edges: [Edge.new("fork", "a", %{})]}

      outcome =
        AttractorEx.Handlers.Parallel.execute(
          node,
          %{},
          graph,
          unique_stage_dir("parallel_max_parallel_fallback"),
          parallel_branch_runner: fn _to, _ctx, _graph, _opts -> Outcome.success() end
        )

      assert outcome.status == :success
    end

    test "parallel fan-in selects best candidate heuristically" do
      node = Node.new("join", %{"shape" => "tripleoctagon"})

      context = %{
        "parallel.results" => [
          %{"id" => "candidate_b", "status" => "partial_success", "score" => 0.9},
          %{"id" => "candidate_a", "status" => "success", "score" => 0.3}
        ]
      }

      outcome =
        AttractorEx.Handlers.ParallelFanIn.execute(
          node,
          context,
          %Graph{},
          unique_stage_dir("fan_in"),
          []
        )

      assert outcome.status == :success
      assert get_in(outcome.context_updates, ["parallel.fan_in.best_id"]) == "candidate_a"
    end

    test "parallel fan-in fails without results" do
      node = Node.new("join", %{"shape" => "tripleoctagon"})

      outcome =
        AttractorEx.Handlers.ParallelFanIn.execute(
          node,
          %{},
          %Graph{},
          unique_stage_dir("fanin_empty"),
          []
        )

      assert outcome.status == :fail
    end

    test "parallel fan-in uses evaluator when prompt is present" do
      node = Node.new("join", %{"shape" => "tripleoctagon", "prompt" => "rank"})

      context = %{
        "parallel.results" => [
          %{"id" => "a", "status" => "retry"},
          %{"id" => "b", "status" => "fail"}
        ]
      }

      outcome =
        AttractorEx.Handlers.ParallelFanIn.execute(
          node,
          context,
          %Graph{},
          unique_stage_dir("fanin_eval"),
          fan_in_evaluator: fn _ -> %{"id" => "b", "status" => "retry"} end
        )

      assert outcome.status == :success
      assert get_in(outcome.context_updates, ["parallel.fan_in.best_id"]) == "b"
      assert get_in(outcome.context_updates, ["parallel.fan_in.best_outcome"]) == "retry"
    end

    test "parallel fan-in handles atom status ranking and unknown status fallback" do
      node = Node.new("join", %{"shape" => "tripleoctagon"})

      context = %{
        "parallel.results" => [
          %{id: "candidate_retry", status: :retry, score: 0},
          %{id: "candidate_unknown", status: "unknown", score: 100}
        ]
      }

      outcome =
        AttractorEx.Handlers.ParallelFanIn.execute(
          node,
          context,
          %Graph{},
          unique_stage_dir("fanin_atoms"),
          []
        )

      assert outcome.status == :success
      assert get_in(outcome.context_updates, ["parallel.fan_in.best_id"]) == "candidate_retry"
    end

    test "manager loop handler returns success when observed child completes" do
      node =
        Node.new("manager", %{
          "shape" => "house",
          "manager.max_cycles" => 2,
          "manager.actions" => "observe"
        })

      observe = fn _ctx ->
        %{"context.stack.child" => %{"status" => "completed", "outcome" => "success"}}
      end

      outcome =
        AttractorEx.Handlers.StackManagerLoop.execute(
          node,
          %{},
          %Graph{attrs: %{"stack.child_dotfile" => "child.dot"}},
          unique_stage_dir("manager"),
          manager_observe: observe
        )

      assert outcome.status == :success
    end

    test "manager loop returns fail when child status is failed" do
      node =
        Node.new("manager", %{
          "shape" => "house",
          "manager.max_cycles" => 2,
          "manager.actions" => "observe"
        })

      observe = fn _ctx -> %{"context.stack.child.status" => "failed"} end

      outcome =
        AttractorEx.Handlers.StackManagerLoop.execute(
          node,
          %{},
          %Graph{attrs: %{"stack.child_dotfile" => "child.dot"}},
          unique_stage_dir("manager_failed"),
          manager_observe: observe
        )

      assert outcome.status == :fail
      assert outcome.failure_reason =~ "Child failed"
    end

    test "manager loop returns success when stop condition evaluates true" do
      node =
        Node.new("manager", %{
          "shape" => "house",
          "manager.max_cycles" => 2,
          "manager.actions" => "observe,steer",
          "manager.stop_condition" => "custom.ready"
        })

      observe = fn _ctx -> %{"custom" => %{"ready" => true}} end
      steer = fn ctx, _node -> ctx end

      stop_eval = fn expr, ctx ->
        expr == "custom.ready" and get_in(ctx, ["custom", "ready"]) == true
      end

      outcome =
        AttractorEx.Handlers.StackManagerLoop.execute(
          node,
          %{},
          %Graph{attrs: %{"stack.child_dotfile" => "child.dot"}},
          unique_stage_dir("manager_stop"),
          manager_observe: observe,
          manager_steer: steer,
          manager_stop_eval: stop_eval
        )

      assert outcome.status == :success
      assert outcome.notes =~ "Stop condition"
    end

    test "manager loop returns fail when max cycles exceeded" do
      node =
        Node.new("manager", %{
          "shape" => "house",
          "manager.max_cycles" => 1,
          "manager.actions" => "observe",
          "stack.child_autostart" => "false",
          "manager.poll_interval" => "1ms"
        })

      outcome =
        AttractorEx.Handlers.StackManagerLoop.execute(
          node,
          %{},
          %Graph{attrs: %{}},
          unique_stage_dir("manager_max_cycles"),
          manager_observe: fn ctx -> ctx end
        )

      assert outcome.status == :fail
      assert outcome.failure_reason =~ "Max cycles exceeded"
    end

    test "manager loop supports duration units and autostart boolean true" do
      observe = fn _ctx -> %{"context.stack.child.status" => "failed"} end
      starter = fn _dot -> :ok end

      for unit <- ["1m", "1h", "1d"] do
        node =
          Node.new("manager", %{
            "shape" => "house",
            "manager.max_cycles" => 1,
            "manager.actions" => "observe",
            "manager.poll_interval" => unit,
            "stack.child_autostart" => true
          })

        outcome =
          AttractorEx.Handlers.StackManagerLoop.execute(
            node,
            %{},
            %Graph{attrs: %{"stack.child_dotfile" => "child.dot"}},
            unique_stage_dir("manager_units_#{unit}"),
            manager_observe: observe,
            manager_start_child: starter
          )

        assert outcome.status == :fail
      end
    end

    test "manager loop handles parse fallbacks and non-binary truthy path" do
      node =
        Node.new("manager", %{
          "shape" => "house",
          "manager.max_cycles" => %{invalid: true},
          "manager.actions" => "observe",
          "manager.poll_interval" => :bad,
          "stack.child_autostart" => 123
        })

      outcome =
        AttractorEx.Handlers.StackManagerLoop.execute(
          node,
          %{},
          %Graph{attrs: %{}},
          unique_stage_dir("manager_parse_fallbacks"),
          manager_observe: fn _ctx -> %{"context.stack.child.status" => "failed"} end
        )

      assert outcome.status == :fail
    end

    test "manager loop reads flat child outcome keys and parses integer poll interval" do
      node =
        Node.new("manager", %{
          "shape" => "house",
          "manager.max_cycles" => "1",
          "manager.actions" => "observe",
          "manager.poll_interval" => 0
        })

      observe = fn _ctx ->
        %{"context.stack.child.status" => "completed", "context.stack.child.outcome" => "success"}
      end

      outcome =
        AttractorEx.Handlers.StackManagerLoop.execute(
          node,
          %{},
          %Graph{attrs: %{}},
          unique_stage_dir("manager_flat_keys"),
          manager_observe: observe
        )

      assert outcome.status == :success
    end

    test "default handler returns fail when node type is unknown" do
      node = Node.new("mystery", %{"type" => "my.custom.type"})

      outcome =
        AttractorEx.Handlers.Default.execute(node, %{}, %Graph{}, unique_stage_dir("default"), [])

      assert outcome.status == :fail
      assert outcome.failure_reason =~ "No handler found"
    end
  end

  defp unique_stage_dir(tag) do
    path =
      Path.join(
        System.tmp_dir!(),
        "attractor_ex_handler_#{tag}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    path
  end
end
