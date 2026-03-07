defmodule AttractorEx.ValidatorTest do
  use ExUnit.Case, async: true

  alias AttractorEx.{Parser, Validator}

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

    test "warns for codergen nodes without prompt" do
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
      assert Enum.any?(diagnostics, &(&1.code == :codergen_prompt and &1.severity == :warning))
    end

    test "warns when non-exit nodes are unreachable from start" do
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
               &(&1.code == :unreachable_node and &1.severity == :warning and
                   &1.node_id == "orphan")
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
  end
end
