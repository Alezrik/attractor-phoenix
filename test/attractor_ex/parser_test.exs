defmodule AttractorEx.ParserTest do
  use ExUnit.Case, async: true

  alias AttractorEx.Parser

  describe "spec: DOT parsing subset" do
    test "parses graph attrs, node defaults, and chained edges" do
      dot = """
      digraph attractor {
        graph [goal="Ship feature"]
        node [shape=box]
        edge [status="success"]
        start [shape=Mdiamond]
        plan [prompt="Plan for $goal"]
        implement [goal_gate=true]
        done [shape=Msquare]
        start -> plan -> implement
        implement -> done [condition="metrics.pass == true"]
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      assert graph.attrs["goal"] == "Ship feature"
      assert graph.nodes["start"].type == "start"
      assert graph.nodes["plan"].type == "codergen"
      assert graph.nodes["implement"].goal_gate
      assert length(graph.edges) == 3
      assert Enum.at(graph.edges, 0).status == "success"
      assert Enum.at(graph.edges, 2).condition == "metrics.pass == true"
    end

    test "creates implicit nodes referenced only by edges" do
      dot = """
      digraph {
        start [shape=Mdiamond]
        done [shape=Msquare]
        start -> hidden
        hidden -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      assert Map.has_key?(graph.nodes, "hidden")
      assert graph.nodes["hidden"].type == "codergen"
    end

    test "maps canonical shapes to handler types" do
      dot = """
      digraph {
        start [shape=Mdiamond]
        router [shape=diamond]
        fork [shape=component]
        join [shape=tripleoctagon]
        human_gate [shape=hexagon]
        tool [shape=parallelogram, tool_command="echo ok"]
        manager [shape=house]
        done [shape=Msquare]
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      assert graph.nodes["start"].type == "start"
      assert graph.nodes["router"].type == "conditional"
      assert graph.nodes["fork"].type == "parallel"
      assert graph.nodes["join"].type == "parallel.fan_in"
      assert graph.nodes["human_gate"].type == "wait.human"
      assert graph.nodes["tool"].type == "tool"
      assert graph.nodes["manager"].type == "stack.manager_loop"
      assert graph.nodes["done"].type == "exit"
    end
  end
end
