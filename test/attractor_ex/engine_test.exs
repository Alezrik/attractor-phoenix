defmodule AttractorEx.EngineTest do
  use ExUnit.Case, async: true

  alias AttractorEx

  describe "spec: execution engine lifecycle and routing" do
    test "runs a simple pipeline and writes checkpoint + status files" do
      dot = """
      digraph attractor {
        graph [goal="Create hello world"]
        start [shape=Mdiamond]
        plan [shape=box, prompt="Plan for $goal"]
        implement [shape=box, prompt="Implement code", goal_gate=true]
        done [shape=Msquare]
        start -> plan
        plan -> implement
        implement -> done
      }
      """

      assert {:ok, result} =
               AttractorEx.run(dot, %{},
                 logs_root: unique_logs_root("simple"),
                 codergen_backend: AttractorExTest.EchoBackend
               )

      assert result.status == :success
      assert File.exists?(Path.join(result.logs_root, "checkpoint.json"))
      assert File.exists?(Path.join(result.logs_root, "manifest.json"))
      assert File.exists?(Path.join([result.logs_root, "plan", "status.json"]))
      assert File.exists?(Path.join([result.logs_root, "plan", "prompt.md"]))
      assert File.exists?(Path.join([result.logs_root, "plan", "response.md"]))
    end

    test "routes by edge condition first" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        decide [shape=diamond, prompt="route"]
        high [shape=box, prompt="high branch"]
        low [shape=box, prompt="low branch"]
        done [shape=Msquare]
        start -> decide
        decide -> high [condition="metrics.score >= 90"]
        decide -> low
        high -> done
        low -> done
      }
      """

      assert {:ok, result} =
               AttractorEx.run(dot, %{"metrics" => %{"score" => 95}},
                 logs_root: unique_logs_root("condition"),
                 codergen_backend: AttractorExTest.EchoBackend
               )

      assert Enum.any?(result.history, &(&1.node_id == "high"))
      refute Enum.any?(result.history, &(&1.node_id == "low"))
    end

    test "routes by edge status when no condition matches" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        task [shape=box, prompt="do work"]
        failed [shape=box, prompt="recover"]
        done [shape=Msquare]
        start -> task
        task -> failed [status="fail"]
        task -> done
        failed -> done
      }
      """

      assert {:ok, result} =
               AttractorEx.run(dot, %{},
                 logs_root: unique_logs_root("status"),
                 codergen_backend: AttractorExTest.StatusBackend
               )

      assert Enum.any?(result.history, &(&1.node_id == "failed"))
    end

    test "uses default edge when no condition or status route is selected" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        branch [shape=diamond]
        fallback [shape=box, prompt="fallback"]
        done [shape=Msquare]
        start -> branch
        branch -> fallback
        fallback -> done
      }
      """

      assert {:ok, result} =
               AttractorEx.run(dot, %{},
                 logs_root: unique_logs_root("default"),
                 codergen_backend: AttractorExTest.EchoBackend
               )

      assert Enum.any?(result.history, &(&1.node_id == "fallback"))
    end

    test "fails run when no outgoing edge is available" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        task [shape=box, prompt="Task", retry_target="done"]
        done [shape=Msquare]
        start -> task
      }
      """

      assert {:ok, result} = AttractorEx.run(dot, %{}, logs_root: unique_logs_root("no_outgoing"))
      assert result.status == :fail
      assert result.reason =~ "No outgoing edge selected"
    end

    test "enforces goal gate and retries to retry_target until satisfied" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        implement [shape=box, prompt="Implement feature", goal_gate=true, retry_target="implement"]
        done [shape=Msquare]
        start -> implement
        implement -> done
      }
      """

      assert {:ok, result} =
               AttractorEx.run(dot, %{},
                 logs_root: unique_logs_root("goal_gate_retry"),
                 codergen_backend: AttractorExTest.FlakyGoalGateBackend,
                 max_steps: 10
               )

      assert result.status == :success
      assert Enum.count(result.history, &(&1.node_id == "implement")) >= 2
      assert get_in(result.context, ["goal_gate_attempts"]) >= 2
    end

    test "selects edge by preferred label normalization" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        router [shape=box, prompt="route"]
        path_a [shape=box, prompt="a"]
        path_b [shape=box, prompt="b"]
        done [shape=Msquare]
        start -> router
        router -> path_a [label="No - Skip"]
        router -> path_b [label="[Y] Ship It"]
        path_a -> done
        path_b -> done
      }
      """

      assert {:ok, result} =
               AttractorEx.run(dot, %{},
                 logs_root: unique_logs_root("preferred_label"),
                 codergen_backend: AttractorExTest.PreferredLabelBackend
               )

      assert Enum.any?(result.history, &(&1.node_id == "path_b"))
      refute Enum.any?(result.history, &(&1.node_id == "path_a"))
    end

    test "selects edge by suggested_next_ids" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        router [shape=box, prompt="route"]
        path_a [shape=box, prompt="a"]
        path_b [shape=box, prompt="b"]
        done [shape=Msquare]
        start -> router
        router -> path_a
        router -> path_b
        path_a -> done
        path_b -> done
      }
      """

      assert {:ok, result} =
               AttractorEx.run(dot, %{},
                 logs_root: unique_logs_root("suggested_next"),
                 codergen_backend: AttractorExTest.SuggestedNextBackend
               )

      assert Enum.any?(result.history, &(&1.node_id == "path_b"))
      refute Enum.any?(result.history, &(&1.node_id == "path_a"))
    end

    test "selects unconditional edge by highest weight then lexical tiebreak" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        router [shape=diamond]
        alpha [shape=box, prompt="alpha"]
        beta [shape=box, prompt="beta"]
        done [shape=Msquare]
        start -> router
        router -> alpha [weight=10]
        router -> beta [weight=10]
        alpha -> done
        beta -> done
      }
      """

      assert {:ok, result} =
               AttractorEx.run(dot, %{},
                 logs_root: unique_logs_root("weight_lexical"),
                 codergen_backend: AttractorExTest.EchoBackend
               )

      assert Enum.any?(result.history, &(&1.node_id == "alpha"))
      refute Enum.any?(result.history, &(&1.node_id == "beta"))
    end

    test "retries RETRY outcomes according to max_retries and succeeds later" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        task [shape=box, prompt="work", max_retries=3]
        done [shape=Msquare]
        start -> task
        task -> done
      }
      """

      assert {:ok, result} =
               AttractorEx.run(dot, %{},
                 logs_root: unique_logs_root("retry_success"),
                 codergen_backend: AttractorExTest.RetryThenSuccessBackend,
                 retry_sleep: false
               )

      assert result.status == :success
      assert get_in(result.context, ["retry_attempts"]) == 3
      assert File.exists?(Path.join([result.logs_root, "task_attempt_2", "status.json"]))
    end

    test "allow_partial returns PARTIAL_SUCCESS when retries exhausted" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        task [shape=box, prompt="work", max_retries=1, allow_partial=true]
        done [shape=Msquare]
        start -> task
        task -> done
      }
      """

      assert {:ok, result} =
               AttractorEx.run(dot, %{},
                 logs_root: unique_logs_root("allow_partial"),
                 codergen_backend: AttractorExTest.AlwaysRetryBackend,
                 retry_sleep: false
               )

      assert result.outcomes["task"].status == :partial_success
      assert result.status == :success
    end

    test "uses failure routing retry_target when stage fails and no edge selected" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        task [shape=box, prompt="work", retry_target="recover"]
        recover [shape=box, prompt="recover"]
        done [shape=Msquare]
        start -> task
        recover -> done
      }
      """

      assert {:ok, result} =
               AttractorEx.run(dot, %{},
                 logs_root: unique_logs_root("failure_routing"),
                 codergen_backend: AttractorExTest.FailBackend
               )

      assert Enum.any?(result.history, &(&1.node_id == "recover"))
    end

    test "restarts run when selected edge has loop_restart=true" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        task [shape=box, prompt="work"]
        done [shape=Msquare]
        start -> task [loop_restart=true]
        task -> done
      }
      """

      assert {:ok, result} =
               AttractorEx.run(dot, %{},
                 logs_root: unique_logs_root("loop_restart"),
                 codergen_backend: AttractorExTest.EchoBackend,
                 max_steps: 20
               )

      assert result.status == :success
      assert Enum.count(result.history, &(&1.node_id == "task")) == 1
    end

    test "resumes a run from checkpoint.json path" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        plan [shape=box, prompt="plan"]
        implement [shape=box, prompt="implement"]
        done [shape=Msquare]
        start -> plan -> implement -> done
      }
      """

      assert {:ok, interrupted} =
               AttractorEx.run(dot, %{},
                 logs_root: unique_logs_root("resume_path"),
                 codergen_backend: AttractorExTest.EchoBackend,
                 max_steps: 2
               )

      assert interrupted.status == :fail
      checkpoint_path = Path.join(interrupted.logs_root, "checkpoint.json")
      assert File.exists?(checkpoint_path)

      assert {:ok, resumed} =
               AttractorEx.resume(dot, checkpoint_path,
                 codergen_backend: AttractorExTest.EchoBackend,
                 max_steps: 10
               )

      assert resumed.status == :success
      assert Enum.any?(resumed.history, &(&1.node_id == "implement"))
      assert resumed.context["run_id"] == interrupted.context["run_id"]
    end

    test "returns error when checkpoint file path does not exist" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        done [shape=Msquare]
        start -> done
      }
      """

      missing =
        Path.join(
          System.tmp_dir!(),
          "attractor_ex_missing_checkpoint_#{System.unique_integer([:positive])}.json"
        )

      assert {:error, %{error: message}} = AttractorEx.resume(dot, missing)
      assert message =~ "Checkpoint file not found"
    end

    test "applies graph_transforms before validation and execution" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        task [shape=box]
        done [shape=Msquare]
        start -> task -> done
      }
      """

      patch_prompt = fn graph ->
        task = Map.fetch!(graph.nodes, "task")

        patched_task = %{
          task
          | attrs: Map.put(task.attrs, "prompt", "transformed prompt"),
            prompt: "transformed prompt"
        }

        %{graph | nodes: Map.put(graph.nodes, "task", patched_task)}
      end

      assert {:ok, result} =
               AttractorEx.run(dot, %{},
                 logs_root: unique_logs_root("graph_transform_function"),
                 codergen_backend: AttractorExTest.EchoBackend,
                 graph_transforms: [patch_prompt]
               )

      assert result.status == :success

      assert File.read!(Path.join([result.logs_root, "task", "prompt.md"])) ==
               "transformed prompt"
    end

    test "applies built-in variable expansion before execution" do
      dot = """
      digraph attractor {
        graph [goal="Ship release"]
        start [shape=Mdiamond]
        task [shape=box, prompt="Plan for $goal"]
        done [shape=Msquare]
        start -> task -> done
      }
      """

      assert {:ok, result} =
               AttractorEx.run(dot, %{},
                 logs_root: unique_logs_root("builtin_variable_expansion"),
                 codergen_backend: AttractorExTest.EchoBackend
               )

      assert result.status == :success

      assert File.read!(Path.join([result.logs_root, "task", "prompt.md"])) ==
               "Plan for Ship release"
    end

    test "supports module graph transforms via transform/1" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        task [shape=box]
        done [shape=Msquare]
        start -> task -> done
      }
      """

      assert {:ok, result} =
               AttractorEx.run(dot, %{},
                 logs_root: unique_logs_root("graph_transform_module"),
                 codergen_backend: AttractorExTest.EchoBackend,
                 graph_transforms: [AttractorExTest.GraphTransform]
               )

      assert result.status == :success

      assert File.read!(Path.join([result.logs_root, "task", "prompt.md"])) ==
               "module transformed"
    end

    test "returns error when graph transform is invalid" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        done [shape=Msquare]
        start -> done
      }
      """

      invalid_transform = fn _graph -> :invalid end

      assert {:error, %{error: message}} =
               AttractorEx.run(dot, %{}, graph_transforms: [invalid_transform])

      assert message =~ "Graph transform must return"
    end
  end

  defp unique_logs_root(tag) do
    Path.join(
      System.tmp_dir!(),
      "attractor_ex_tests_#{tag}_#{System.unique_integer([:positive])}"
    )
  end
end
