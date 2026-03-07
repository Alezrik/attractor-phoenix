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

    test "flattens inline and nested subgraphs into regular statements" do
      dot = """
      digraph attractor {
        start [shape=Mdiamond];
        done [shape=Msquare];
        subgraph cluster_outer { plan [shape=box]; subgraph cluster_inner { plan -> build; } build -> done; }
        start -> plan;
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      assert Map.has_key?(graph.nodes, "plan")
      assert Map.has_key?(graph.nodes, "build")
      assert Enum.any?(graph.edges, &(&1.from == "start" and &1.to == "plan"))
      assert Enum.any?(graph.edges, &(&1.from == "plan" and &1.to == "build"))
      assert Enum.any?(graph.edges, &(&1.from == "build" and &1.to == "done"))
    end

    test "parses quoted node identifiers in node declarations and chained edges" do
      dot = """
      digraph "attractor-flow" {
        "start-node" [shape=Mdiamond]
        "plan step" [shape=box, prompt="Plan // keep text"]
        "done-node" [shape=Msquare]
        "start-node" -> "plan step" -> "done-node"
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      assert graph.id == "attractor-flow"
      assert Map.has_key?(graph.nodes, "start-node")
      assert Map.has_key?(graph.nodes, "plan step")
      assert graph.nodes["plan step"].prompt == "Plan // keep text"
      assert Enum.any?(graph.edges, &(&1.from == "start-node" and &1.to == "plan step"))
      assert Enum.any?(graph.edges, &(&1.from == "plan step" and &1.to == "done-node"))
    end

    test "preserves comment markers inside quoted values while stripping real comments" do
      dot = """
      digraph attractor {
        // graph level note
        start [shape=Mdiamond, prompt="Keep // inline markers"]
        /* remove this block comment */
        done [shape=Msquare, prompt="Keep /* block */ markers"]
        start -> done [condition="result == \\"//ok\\""]
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      assert graph.nodes["start"].prompt == "Keep // inline markers"
      assert graph.nodes["done"].prompt == "Keep /* block */ markers"
      assert Enum.at(graph.edges, 0).condition == ~s(result == "//ok")
    end

    test "applies model_stylesheet rules with selector precedence" do
      stylesheet =
        ~s({"node":{"reasoning_effort":"low","llm_provider":"openai"},"type=codergen":{"llm_model":"gpt-4o-mini"},".critical":{"reasoning_effort":"medium"},"#review":{"reasoning_effort":"high"}})

      escaped_stylesheet = String.replace(stylesheet, "\"", "\\\"")

      dot = """
      digraph attractor {
        graph [model_stylesheet="#{escaped_stylesheet}"]
        start [shape=Mdiamond]
        review [shape=box, class="critical"]
        summarize [shape=box]
        done [shape=Msquare]
        start -> review -> summarize -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      assert graph.nodes["summarize"].attrs["llm_model"] == "gpt-4o-mini"
      assert graph.nodes["summarize"].attrs["llm_provider"] == "openai"
      assert graph.nodes["summarize"].attrs["reasoning_effort"] == "low"
      assert graph.nodes["review"].attrs["reasoning_effort"] == "high"
    end

    test "applies CSS model_stylesheet rules from graph attrs" do
      stylesheet =
        "* { llm_provider: anthropic; llm_model: claude-sonnet-4-5; } .code { llm_model: claude-opus-4-6; } #critical_review { llm_model: gpt-5.2; llm_provider: openai; reasoning_effort: high; }"

      escaped_stylesheet = String.replace(stylesheet, "\"", "\\\"")

      dot = """
      digraph attractor {
        graph [model_stylesheet="#{escaped_stylesheet}"]
        start [shape=Mdiamond]
        plan [shape=box]
        implement [shape=box, class="code"]
        critical_review [shape=box, class="code"]
        done [shape=Msquare]
        start -> plan -> implement -> critical_review -> done
      }
      """

      assert {:ok, graph} = Parser.parse(dot)
      assert graph.nodes["plan"].attrs["llm_provider"] == "anthropic"
      assert graph.nodes["plan"].attrs["llm_model"] == "claude-sonnet-4-5"
      assert graph.nodes["implement"].attrs["llm_model"] == "claude-opus-4-6"
      assert graph.nodes["critical_review"].attrs["llm_model"] == "gpt-5.2"
      assert graph.nodes["critical_review"].attrs["llm_provider"] == "openai"
      assert graph.nodes["critical_review"].attrs["reasoning_effort"] == "high"
    end

    test "returns an error when model_stylesheet is invalid JSON" do
      dot = """
      digraph attractor {
        graph [model_stylesheet="not-json"]
        start [shape=Mdiamond]
        done [shape=Msquare]
        start -> done
      }
      """

      assert {:error, message} = Parser.parse(dot)
      assert message =~ "model_stylesheet is not valid JSON or CSS stylesheet"
    end
  end
end
