defmodule AttractorEx.AuthoringTest do
  use ExUnit.Case, async: true

  alias AttractorEx.{Authoring, Graph, Node, Edge}

  test "analyze returns canonical dot, graph json, diagnostics, and autofixes" do
    dot = """
    digraph attractor {
      done [shape=Msquare]
      work [shape=parallelogram, tool_command="echo hi"]
      done -> work
    }
    """

    assert {:ok, payload} = Authoring.analyze(dot)

    assert payload["dot"] =~ ~s(digraph attractor)
    assert payload["graph"]["nodes"]["done"]["type"] == "exit"
    assert payload["graph"]["nodes"]["work"]["type"] == "tool"

    assert Enum.any?(payload["diagnostics"], &(&1["code"] == "start_node"))
    assert Enum.any?(payload["autofixes"], &(&1["id"] == "add_start_node"))
    assert Enum.any?(payload["autofixes"], &(&1["id"] == "remove_exit_outgoing_edges"))
  end

  test "analyze returns parse diagnostics for invalid dot" do
    assert {:error, payload} = Authoring.analyze("not dot")
    assert payload["error"] =~ "Invalid DOT input"
    assert [%{"code" => "parse_error", "severity" => "error"}] = payload["diagnostics"]
  end

  test "analyze returns a clean payload without autofixes for a valid graph" do
    dot = """
    digraph attractor {
      graph [goal="Ship", default_max_retry=2]
      start [shape=Mdiamond]
      done [shape=Msquare]
      start -> done [weight=1]
    }
    """

    assert {:ok, payload} = Authoring.analyze(dot)
    assert payload["diagnostics"] == []
    assert payload["autofixes"] == []
    assert payload["graph"]["attrs"]["goal"] == "Ship"
  end

  test "transform formats dot canonically" do
    dot = """
    digraph attractor {
      start [shape=Mdiamond]
      done [shape=Msquare]
      start -> done
    }
    """

    assert {:ok, payload} = Authoring.transform("format", %{"dot" => dot})
    assert payload["dot"] =~ ~s(start [shape="Mdiamond", label="start"])
    assert payload["dot"] =~ ~s(done [shape="Msquare", label="done"])
  end

  test "format accepts normalized graph structs directly" do
    graph = %Graph{
      id: "custom-graph",
      attrs: %{"goal" => "Ship", "default_max_retry" => 2},
      node_defaults: %{"timeout" => "30s"},
      edge_defaults: %{"fidelity" => "compact"},
      nodes: %{
        "start" => Node.new("start", %{"shape" => "Mdiamond"}),
        "gate node" =>
          Node.new("gate node", %{
            "shape" => "hexagon",
            "type" => "wait_for_human",
            "prompt" => "Approve?\nNow",
            "human.required" => true
          }),
        "done" => Node.new("done", %{"shape" => "Msquare"})
      },
      edges: [
        Edge.new("start", "gate node", %{"condition" => "true", "weight" => 1.5}),
        Edge.new("gate node", "done", %{"status" => "success", "loop_restart" => false})
      ]
    }

    dot = Authoring.format(graph)

    assert dot =~ ~s(digraph custom-graph {)
    assert dot =~ ~s(graph [goal="Ship", default_max_retry=2])
    assert dot =~ ~s(node [timeout="30s"])
    assert dot =~ ~s(edge [fidelity="compact"])

    assert dot =~
             ~s("gate node" [shape="hexagon", label="gate node", type="wait_for_human", prompt="Approve?\\nNow", human.required=true])

    assert dot =~ ~s(start -> "gate node" [condition="true", weight=1.50000000000000000000e+00])
  end

  test "transform applies supported autofixes" do
    dot = """
    digraph attractor {
      work [shape=parallelogram, tool_command="echo hi"]
      done [shape=Msquare]
      work -> done
    }
    """

    assert {:ok, payload} =
             Authoring.transform("apply_fix", %{"dot" => dot, "fix_id" => "add_start_node"})

    assert payload["graph"]["nodes"]["start"]["type"] == "start"
    assert payload["dot"] =~ ~s(start [shape="Mdiamond", label="start"])
  end

  test "autofixes can remove invalid start and exit routing and connect dead ends" do
    dot = """
    digraph attractor {
      start [shape=Mdiamond]
      review [shape=parallelogram, tool_command="echo review"]
      done [shape=Msquare]
      stray [shape=box, prompt="stray"]
      review -> start
      start -> review
      review -> done
      done -> review
    }
    """

    assert {:ok, payload} =
             Authoring.transform("apply_fix", %{
               "dot" => dot,
               "fix_id" => "remove_start_incoming_edges"
             })

    refute payload["dot"] =~ "review -> start"

    assert {:ok, payload} =
             Authoring.transform("apply_fix", %{
               "dot" => payload["dot"],
               "fix_id" => "remove_exit_outgoing_edges"
             })

    refute payload["dot"] =~ "done -> review"

    assert {:ok, payload} =
             Authoring.transform("apply_fix", %{
               "dot" => payload["dot"],
               "fix_id" => "connect_dead_ends_to_exit"
             })

    assert payload["dot"] =~ "stray -> done"
  end

  test "format retains explicit node type when shape alone is ambiguous" do
    dot = """
    digraph attractor {
      start [shape=Mdiamond]
      gate [shape=hexagon, type="wait_for_human", prompt="Approve?"]
      done [shape=Msquare]
      start -> gate
      gate -> done
    }
    """

    assert {:ok, payload} = Authoring.transform("format", %{"dot" => dot})

    assert payload["dot"] =~
             ~s(gate [shape="hexagon", label="gate", type="wait_for_human", prompt="Approve?"])
  end

  test "transform rejects unknown templates, unknown fixes, and unsupported actions" do
    dot = """
    digraph attractor {
      start [shape=Mdiamond]
      done [shape=Msquare]
      start -> done
    }
    """

    assert {:error, %{"error" => "unknown template", "template_id" => "missing"}} =
             Authoring.transform("apply_template", %{"template_id" => "missing"})

    assert {:error, %{"error" => "unsupported autofix: missing_fix"}} =
             Authoring.transform("apply_fix", %{"dot" => dot, "fix_id" => "missing_fix"})

    assert {:error, %{"error" => "unsupported transform action: nope"}} =
             Authoring.transform("nope", %{"dot" => dot})
  end

  test "transform rejects missing dot payloads" do
    assert {:error, %{"error" => "dot is required"}} = Authoring.transform("format", %{})
  end

  test "apply_fix handles no-op and collision cases" do
    dot = """
    digraph attractor {
      start [shape=Mdiamond]
      start_1 [shape=parallelogram, tool_command="echo alternate"]
      done [shape=Msquare]
      start -> done
    }
    """

    assert {:ok, payload} =
             Authoring.transform("apply_fix", %{"dot" => dot, "fix_id" => "add_start_node"})

    refute payload["dot"] =~ "start_2"

    dot_without_exit = """
    digraph attractor {
      start [shape=Mdiamond]
      done [shape=parallelogram, tool_command="echo not-exit"]
      done_1 [shape=parallelogram, tool_command="echo reserve"]
      start -> done
    }
    """

    assert {:ok, payload} =
             Authoring.transform("apply_fix", %{
               "dot" => dot_without_exit,
               "fix_id" => "add_exit_node"
             })

    assert payload["graph"]["nodes"]["done_2"]["type"] == "exit"
  end

  test "apply_fix handles graphs missing a start or exit for routing repairs" do
    dot_without_start = """
    digraph attractor {
      work [shape=parallelogram, tool_command="echo hi"]
      done [shape=Msquare]
      work -> done
    }
    """

    assert {:ok, payload} =
             Authoring.transform("apply_fix", %{
               "dot" => dot_without_start,
               "fix_id" => "remove_start_incoming_edges"
             })

    assert payload["graph"]["nodes"]["done"]["type"] == "exit"

    dot_without_exit = """
    digraph attractor {
      start [shape=Mdiamond]
      work [shape=parallelogram, tool_command="echo hi"]
      start -> work
    }
    """

    assert {:error, %{"error" => "cannot connect dead ends without an exit node"}} =
             Authoring.transform("apply_fix", %{
               "dot" => dot_without_exit,
               "fix_id" => "connect_dead_ends_to_exit"
             })
  end

  test "transform loads built-in templates" do
    assert {:ok, payload} =
             Authoring.transform("apply_template", %{"template_id" => "approval_gate"})

    assert payload["graph"]["attrs"]["label"] == "approval-gate"
    assert Map.has_key?(payload["graph"]["nodes"], "gate")
  end

  test "templates exposes the built-in catalog" do
    templates = Authoring.templates()
    assert length(templates) >= 3
    assert Enum.any?(templates, &(&1.id == "parallel_review"))
  end
end
