defmodule AttractorEx.ValidatorTest do
  use ExUnit.Case, async: true

  alias AttractorEx.{Edge, Graph, Node, Parser, Validator}

  describe "spec: validation and linting" do
    test "flags missing terminal node" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        start -> plan
        plan [shape=box, prompt="Plan"]
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)
      assert Enum.any?(diagnostics, &(&1.code == :terminal_node and &1.severity == :error))
    end

    test "flags multiple terminal nodes" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        done [shape=Msquare]
        end [shape=Msquare]
        start -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)
      assert Enum.any?(diagnostics, &(&1.code == :terminal_node and &1.severity == :error))
    end

    test "flags missing start node" do
      dot = """
      digraph attractor {
        done [shape=Msquare]
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)
      assert Enum.any?(diagnostics, &(&1.code == :start_node and &1.severity == :error))
    end

    test "flags incoming edge into start" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        done [shape=Msquare]
        done -> start
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)
      assert Enum.any?(diagnostics, &(&1.code == :start_no_incoming and &1.severity == :error))
    end

    test "flags outgoing edges from exit" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        done [shape=Msquare]
        start -> done
        done -> start
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)
      assert Enum.any?(diagnostics, &(&1.code == :exit_no_outgoing and &1.severity == :error))
    end

    test "warns for goal gate nodes missing retry targets" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        implement [shape=box, prompt="Implement", goal_gate=true]
        done [shape=Msquare]
        start -> implement
        implement -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :goal_gate_has_retry and &1.severity == :warning)
             )
    end

    test "warns for llm-backed box nodes without prompt or label" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        task [shape=box]
        done [shape=Msquare]
        start -> task
        task -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :prompt_on_llm_nodes and &1.severity == :warning)
             )
    end

    test "accepts llm-backed box nodes with a label even when prompt is absent" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        task [shape=box, label="Plan task"]
        done [shape=Msquare]
        start -> task
        task -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)
      refute Enum.any?(diagnostics, &(&1.code == :prompt_on_llm_nodes and &1.node_id == "task"))
    end

    test "warns when node type is not recognized by the handler registry" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        custom [type="my.custom.handler", prompt="Plan"]
        done [shape=Msquare]
        start -> custom
        custom -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :type_known and &1.severity == :warning and &1.node_id == "custom")
             )
    end

    test "warns on invalid graph, node, and edge fidelity values" do
      dot = """
      digraph attractor {
        graph [default_fidelity="ultra"]
        start [shape=Mdiamond]
        task [shape=box, prompt="Plan", fidelity="verbose"]
        done [shape=Msquare]
        start -> task [fidelity="invalid"]
        task -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :fidelity_valid and &1.severity == :warning and is_nil(&1.node_id) and
                   is_nil(&1.edge))
             )

      assert Enum.any?(
               diagnostics,
               &(&1.code == :fidelity_valid and &1.severity == :warning and &1.node_id == "task")
             )

      assert Enum.any?(
               diagnostics,
               &(&1.code == :fidelity_valid and &1.severity == :warning and
                   &1.edge == {"start", "task"})
             )
    end

    test "flags unreachable nodes as reachability errors" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        done [shape=Msquare]
        orphan [shape=box, prompt="Orphan work"]
        start -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :reachability and &1.severity == :error and
                   &1.node_id == "orphan")
             )
    end

    test "flags missing edge targets" do
      graph = %Graph{
        nodes: %{
          "start" => Node.new("start", %{"shape" => "Mdiamond"}),
          "done" => Node.new("done", %{"shape" => "Msquare"})
        },
        edges: [Edge.new("start", "missing", %{}), Edge.new("missing", "done", %{})]
      }

      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :edge_target_exists and &1.severity == :error and
                   &1.edge == {"start", "missing"})
             )
    end

    test "flags missing edge sources" do
      graph = %Graph{
        nodes: %{
          "start" => Node.new("start", %{"shape" => "Mdiamond"}),
          "done" => Node.new("done", %{"shape" => "Msquare"})
        },
        edges: [Edge.new("missing", "done", %{})]
      }

      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :edge_source_exists and &1.severity == :error and
                   &1.edge == {"missing", "done"})
             )
    end

    test "warns for non-exit dead-end nodes" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        task [shape=box, prompt="Do work"]
        done [shape=Msquare]
        start -> task
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :dead_end_node and &1.severity == :warning and &1.node_id == "task")
             )
    end

    test "flags missing retry_target references" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        task [shape=box, prompt="Do work", retry_target="missing"]
        done [shape=Msquare]
        start -> task
        task -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :retry_target_missing and &1.severity == :error and
                   &1.node_id == "task")
             )
    end

    test "flags missing fallback_retry_target references" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        task [shape=box, prompt="Do work", fallback_retry_target="missing"]
        done [shape=Msquare]
        start -> task
        task -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :fallback_retry_target_missing and &1.severity == :error and
                   &1.node_id == "task")
             )
    end

    test "warns on invalid graph default_max_retry and node max_retries values" do
      dot = """
      digraph attractor {
        graph [default_max_retry="later"]
        start [shape=Mdiamond]
        task [shape=box, prompt="Do work", max_retries="-1"]
        done [shape=Msquare]
        start -> task
        task -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :default_max_retry_invalid and &1.severity == :warning)
             )

      assert Enum.any?(
               diagnostics,
               &(&1.code == :max_retries_invalid and &1.severity == :warning and
                   &1.node_id == "task")
             )
    end

    test "accepts non-negative graph default_max_retry and node max_retries values" do
      dot = """
      digraph attractor {
        graph [default_max_retry="2"]
        start [shape=Mdiamond]
        task [shape=box, prompt="Do work", max_retries="0"]
        done [shape=Msquare]
        start -> task
        task -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      refute Enum.any?(diagnostics, &(&1.code == :default_max_retry_invalid))
      refute Enum.any?(diagnostics, &(&1.code == :max_retries_invalid))
    end

    test "flags missing graph retry_target references" do
      dot = """
      digraph attractor {
        graph [retry_target="missing"]
        start [shape=Mdiamond]
        task [shape=box, prompt="Do work"]
        done [shape=Msquare]
        start -> task
        task -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :graph_retry_target_missing and &1.severity == :error and
                   is_nil(&1.node_id))
             )
    end

    test "flags missing graph fallback_retry_target references" do
      dot = """
      digraph attractor {
        graph [fallback_retry_target="missing"]
        start [shape=Mdiamond]
        task [shape=box, prompt="Do work"]
        done [shape=Msquare]
        start -> task
        task -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :graph_fallback_retry_target_missing and &1.severity == :error and
                   is_nil(&1.node_id))
             )
    end

    test "flags wait.human nodes with no outgoing choices" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        gate [shape=hexagon]
        done [shape=Msquare]
        start -> gate
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)
      assert Enum.any?(diagnostics, &(&1.code == :human_gate_choices and &1.severity == :error))
    end

    test "warns when human.default_choice does not match any outgoing choice" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        gate [shape=hexagon, human.default_choice="ship"]
        done [shape=Msquare]
        start -> gate
        gate -> done [label="[A] Approve"]
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :human_default_choice and &1.severity == :warning)
             )
    end

    test "warns when wait.human prompt is missing" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        gate [shape=hexagon]
        done [shape=Msquare]
        start -> gate
        gate -> done [label="[A] Approve"]
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :human_gate_prompt and &1.severity == :warning and
                   &1.node_id == "gate")
             )
    end

    test "warns when human.default_choice is ambiguous" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        gate [shape=hexagon, prompt="Choose", human.default_choice="A"]
        done [shape=Msquare]
        retry [shape=box, prompt="Retry"]
        start -> gate
        gate -> done [label="[A] Approve"]
        gate -> retry [label="[A] Ask again"]
        retry -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :human_default_choice_ambiguous and &1.severity == :warning and
                   &1.node_id == "gate")
             )
    end

    test "warns when wait.human timeout is set without default choice" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        gate [shape=hexagon, human.timeout="30s"]
        done [shape=Msquare]
        start -> gate
        gate -> done [label="[A] Approve"]
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :human_timeout_without_default and &1.severity == :warning and
                   &1.node_id == "gate")
             )
    end

    test "warns when wait.human timeout format is invalid" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        gate [shape=hexagon, human.timeout="later", human.default_choice="done"]
        done [shape=Msquare]
        start -> gate
        gate -> done [label="[D] Done"]
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :human_timeout_invalid and &1.severity == :warning and
                   &1.node_id == "gate")
             )
    end

    test "accepts positive wait.human timeout values" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        gate [shape=hexagon, human.timeout="30s", human.default_choice="done"]
        done [shape=Msquare]
        start -> gate
        gate -> done [label="[D] Done"]
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      refute Enum.any?(diagnostics, &(&1.code == :human_timeout_invalid))
    end

    test "warns when wait.human choices collide on accelerator keys" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        gate [shape=hexagon]
        done [shape=Msquare]
        retry [shape=box, prompt="Retry"]
        start -> gate
        gate -> done [label="[A] Approve"]
        gate -> retry [label="[A] Ask again"]
        retry -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :human_gate_duplicate_keys and &1.severity == :warning and
                   &1.node_id == "gate")
             )
    end

    test "warns when human.multiple is invalid or has too few choices" do
      invalid_dot = """
      digraph attractor {
        start [shape=Mdiamond]
        gate [shape=hexagon, prompt="Choose", human.multiple="later"]
        done [shape=Msquare]
        start -> gate
        gate -> done [label="[D] Done"]
      }
      """

      underspecified_dot = """
      digraph attractor {
        start [shape=Mdiamond]
        gate [shape=hexagon, prompt="Choose", human.multiple=true]
        done [shape=Msquare]
        start -> gate
        gate -> done [label="[D] Done"]
      }
      """

      assert {:ok, invalid_graph} = Parser.parse(invalid_dot)
      assert {:ok, underspecified_graph} = Parser.parse(underspecified_dot)

      invalid_diagnostics = Validator.validate(invalid_graph)
      underspecified_diagnostics = Validator.validate(underspecified_graph)

      assert Enum.any?(
               invalid_diagnostics,
               &(&1.code == :human_multiple_invalid and &1.severity == :warning and
                   &1.node_id == "gate")
             )

      assert Enum.any?(
               underspecified_diagnostics,
               &(&1.code == :human_multiple_requires_multiple_choices and
                   &1.severity == :warning and &1.node_id == "gate")
             )
    end

    test "supports custom lint rules via validate/2 custom_rules option" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        done [shape=Msquare]
        start -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)

      custom_rule = fn _graph ->
        %{
          severity: :warning,
          code: :custom_example,
          message: "custom lint triggered",
          node_id: "start"
        }
      end

      diagnostics = Validator.validate(graph, custom_rules: [custom_rule])

      assert Enum.any?(
               diagnostics,
               &(&1.code == :custom_example and &1.severity == :warning and &1.node_id == "start")
             )
    end

    test "warns on invalid codergen LLM attribute values" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        task [shape=box, prompt="Do work", reasoning_effort="extreme", temperature="nope", max_tokens="zero", llm_provider="openai"]
        done [shape=Msquare]
        start -> task
        task -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :reasoning_effort_invalid and &1.severity == :warning and
                   &1.node_id == "task")
             )

      assert Enum.any?(
               diagnostics,
               &(&1.code == :temperature_invalid and &1.severity == :warning and
                   &1.node_id == "task")
             )

      assert Enum.any?(
               diagnostics,
               &(&1.code == :max_tokens_invalid and &1.severity == :warning and
                   &1.node_id == "task")
             )

      assert Enum.any?(
               diagnostics,
               &(&1.code == :llm_provider_without_model and &1.severity == :warning and
                   &1.node_id == "task")
             )
    end

    test "warns on invalid parallel attributes" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        fork [shape=component, join_policy="sometimes", max_parallel="zero", k="two", quorum_ratio="2.0"]
        done [shape=Msquare]
        alt [shape=box, prompt="Alt"]
        start -> fork
        fork -> done
        fork -> alt
        alt -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :parallel_join_policy_invalid and &1.node_id == "fork")
             )

      assert Enum.any?(
               diagnostics,
               &(&1.code == :parallel_max_parallel_invalid and &1.node_id == "fork")
             )

      assert Enum.any?(diagnostics, &(&1.code == :parallel_k_unused and &1.node_id == "fork"))

      assert Enum.any?(
               diagnostics,
               &(&1.code == :parallel_quorum_ratio_unused and &1.node_id == "fork")
             )
    end

    test "warns on missing and invalid k_of_n and quorum settings" do
      missing_k_dot = """
      digraph attractor {
        start [shape=Mdiamond]
        fork [shape=component, join_policy="k_of_n"]
        done [shape=Msquare]
        alt [shape=box, prompt="Alt"]
        start -> fork
        fork -> done
        fork -> alt
        alt -> done
      }
      """

      invalid_quorum_dot = """
      digraph attractor {
        start [shape=Mdiamond]
        fork [shape=component, join_policy="quorum", quorum_ratio="0"]
        done [shape=Msquare]
        alt [shape=box, prompt="Alt"]
        start -> fork
        fork -> done
        fork -> alt
        alt -> done
      }
      """

      assert {:ok, missing_k_graph} = Parser.parse(missing_k_dot)
      assert {:ok, invalid_quorum_graph} = Parser.parse(invalid_quorum_dot)

      missing_k_diagnostics = Validator.validate(missing_k_graph)
      invalid_quorum_diagnostics = Validator.validate(invalid_quorum_graph)

      assert Enum.any?(
               missing_k_diagnostics,
               &(&1.code == :parallel_k_missing and &1.node_id == "fork")
             )

      assert Enum.any?(
               invalid_quorum_diagnostics,
               &(&1.code == :parallel_quorum_ratio_invalid and &1.node_id == "fork")
             )
    end

    test "warns on invalid k_of_n value and missing quorum_ratio" do
      invalid_k_dot = """
      digraph attractor {
        start [shape=Mdiamond]
        fork [shape=component, join_policy="k_of_n", k="zero"]
        done [shape=Msquare]
        alt [shape=box, prompt="Alt"]
        start -> fork
        fork -> done
        fork -> alt
        alt -> done
      }
      """

      missing_quorum_dot = """
      digraph attractor {
        start [shape=Mdiamond]
        fork [shape=component, join_policy="quorum"]
        done [shape=Msquare]
        alt [shape=box, prompt="Alt"]
        start -> fork
        fork -> done
        fork -> alt
        alt -> done
      }
      """

      assert {:ok, invalid_k_graph} = Parser.parse(invalid_k_dot)
      assert {:ok, missing_quorum_graph} = Parser.parse(missing_quorum_dot)

      invalid_k_diagnostics = Validator.validate(invalid_k_graph)
      missing_quorum_diagnostics = Validator.validate(missing_quorum_graph)

      assert Enum.any?(
               invalid_k_diagnostics,
               &(&1.code == :parallel_k_invalid and &1.node_id == "fork")
             )

      assert Enum.any?(
               missing_quorum_diagnostics,
               &(&1.code == :parallel_quorum_ratio_missing and &1.node_id == "fork")
             )
    end

    test "warns on invalid stack manager loop attributes" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        manager [shape=house, manager.actions="observe,panic", manager.max_cycles="zero", manager.poll_interval="-5s"]
        done [shape=Msquare]
        start -> manager
        manager -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :manager_actions_invalid and &1.node_id == "manager")
             )

      assert Enum.any?(
               diagnostics,
               &(&1.code == :manager_max_cycles_invalid and &1.node_id == "manager")
             )

      assert Enum.any?(
               diagnostics,
               &(&1.code == :manager_poll_interval_invalid and &1.node_id == "manager")
             )

      assert Enum.any?(
               diagnostics,
               &(&1.code == :manager_child_dotfile_missing and &1.node_id == "manager")
             )
    end

    test "warns when manager.actions resolves to no actions" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        manager [shape=house, manager.actions=" , , "]
        done [shape=Msquare]
        start -> manager
        manager -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :manager_actions_invalid and &1.node_id == "manager")
             )
    end

    test "accepts valid parallel and stack manager attributes" do
      dot = """
      digraph attractor {
        graph [stack.child_dotfile="child.dot"]
        start [shape=Mdiamond]
        fork [shape=component, join_policy="quorum", max_parallel="2", quorum_ratio="0.5"]
        manager [shape=house, manager.actions="observe,wait", manager.max_cycles="3", manager.poll_interval="500ms", stack.child_autostart="false"]
        done [shape=Msquare]
        start -> fork
        fork -> manager
        fork -> done
        manager -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      refute Enum.any?(diagnostics, &(&1.code == :parallel_join_policy_invalid))
      refute Enum.any?(diagnostics, &(&1.code == :parallel_max_parallel_invalid))
      refute Enum.any?(diagnostics, &(&1.code == :parallel_quorum_ratio_missing))
      refute Enum.any?(diagnostics, &(&1.code == :parallel_quorum_ratio_invalid))
      refute Enum.any?(diagnostics, &(&1.code == :manager_actions_invalid))
      refute Enum.any?(diagnostics, &(&1.code == :manager_max_cycles_invalid))
      refute Enum.any?(diagnostics, &(&1.code == :manager_poll_interval_invalid))
      refute Enum.any?(diagnostics, &(&1.code == :manager_child_dotfile_missing))
    end

    test "accepts valid codergen LLM attribute values" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        task [shape=box, prompt="Do work", reasoning_effort="medium", temperature="0.3", max_tokens="256", llm_provider="openai", llm_model="gpt-5.2"]
        done [shape=Msquare]
        start -> task
        task -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      refute Enum.any?(diagnostics, &(&1.code == :reasoning_effort_invalid))
      refute Enum.any?(diagnostics, &(&1.code == :temperature_invalid))
      refute Enum.any?(diagnostics, &(&1.code == :max_tokens_invalid))
      refute Enum.any?(diagnostics, &(&1.code == :llm_provider_without_model))
    end

    test "warns for stylesheet declaration issues" do
      dot = """
      digraph attractor {
        model_stylesheet="* { llm_provider: openai; unsupported_property: foo; invalid_decl; }"
        start [shape=Mdiamond]
        done [shape=Msquare]
        start -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :model_stylesheet_css_property_unknown and &1.severity == :warning)
             )

      assert Enum.any?(
               diagnostics,
               &(&1.code == :model_stylesheet_css_declaration_invalid and &1.severity == :warning)
             )
    end

    test "flags invalid stylesheet syntax as an error" do
      graph = %Graph{
        attrs: %{"model_stylesheet" => ~s(* { llm_provider: openai;)},
        nodes: %{
          "start" => Node.new("start", %{"shape" => "Mdiamond"}),
          "done" => Node.new("done", %{"shape" => "Msquare"})
        },
        edges: [Edge.new("start", "done", %{})]
      }

      diagnostics = Validator.validate(graph)

      assert Enum.any?(
               diagnostics,
               &(&1.code == :stylesheet_syntax and &1.severity == :error)
             )
    end

    test "handles invalid and crashing custom rules gracefully" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        done [shape=Msquare]
        start -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)

      crashing_rule = fn _graph -> raise "boom" end
      invalid_rule = fn _graph -> :invalid end

      diagnostics =
        Validator.validate(graph,
          custom_rules: [crashing_rule, invalid_rule, AttractorEx.Validator]
        )

      assert Enum.any?(
               diagnostics,
               &(&1.code == :custom_rule_invalid and &1.severity == :warning)
             )
    end

    test "accepts custom rule modules implementing validate/1" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond]
        done [shape=Msquare]
        start -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      diagnostics = Validator.validate(graph, custom_rules: [AttractorExTest.ValidatorRule])

      assert Enum.any?(
               diagnostics,
               &(&1.code == :custom_module_rule and &1.severity == :warning and
                   &1.node_id == "done")
             )
    end

    test "validate_or_raise raises when error-severity diagnostics are present" do
      dot = """
      digraph attractor {
        done [shape=Msquare]
      }
      """

      assert {:ok, graph} = Parser.parse(dot)

      assert_raise ArgumentError, ~r/Attractor validation failed/, fn ->
        Validator.validate_or_raise(graph)
      end
    end
  end
end
