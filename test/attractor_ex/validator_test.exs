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
  end
end
