defmodule AttractorEx.VariableExpansionPropertyTest do
  use ExUnit.Case, async: true
  use PropCheck, default_opts: [numtests: 100]

  import AttractorEx.TestGenerators

  alias AttractorEx.{Edge, Graph, Node, Transforms.VariableExpansion}

  property "transform replaces every $goal occurrence across graph attrs, nodes, and edges" do
    forall [goal, prefix, suffix] <- [nonempty_identifier(), identifier(), identifier()] do
      template = prefix <> "$goal" <> suffix <> "$goal"

      graph = %Graph{
        attrs: %{"goal" => goal, "summary" => template},
        nodes: %{"plan" => Node.new("plan", %{"prompt" => template, "shape" => "box"})},
        edges: [Edge.new("plan", "done", %{"label" => template})]
      }

      expanded = VariableExpansion.transform(graph)
      expected = prefix <> goal <> suffix <> goal

      expanded.attrs["summary"] == expected and
        expanded.nodes["plan"].prompt == expected and
        hd(expanded.edges).attrs["label"] == expected
    end
  end

  property "transform is idempotent for graphs without placeholders" do
    forall [goal, summary, prompt, label] <- [
             nonempty_identifier(),
             identifier(),
             identifier(),
             identifier()
           ] do
      graph = %Graph{
        attrs: %{"goal" => goal, "summary" => summary},
        nodes: %{"plan" => Node.new("plan", %{"prompt" => prompt, "shape" => "box"})},
        edges: [Edge.new("plan", "done", %{"label" => label})]
      }

      VariableExpansion.transform(graph) == graph
    end
  end

  property "transform leaves non-binary attrs untouched" do
    forall goal <- nonempty_identifier() do
      graph = %Graph{
        attrs: %{"goal" => goal, "attempts" => 3},
        nodes: %{"plan" => Node.new("plan", %{"goal_gate" => true, "shape" => "box"})},
        edges: [Edge.new("plan", "done", %{"score" => 0.9})]
      }

      expanded = VariableExpansion.transform(graph)

      expanded.attrs["attempts"] == 3 and expanded.nodes["plan"].goal_gate == true and
        hd(expanded.edges).attrs["score"] == 0.9
    end
  end
end
