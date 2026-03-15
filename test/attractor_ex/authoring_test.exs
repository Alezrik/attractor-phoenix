defmodule AttractorEx.AuthoringTest do
  use ExUnit.Case, async: true

  alias AttractorEx.Authoring

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

  test "transform loads built-in templates" do
    assert {:ok, payload} =
             Authoring.transform("apply_template", %{"template_id" => "approval_gate"})

    assert payload["graph"]["attrs"]["label"] == "approval-gate"
    assert Map.has_key?(payload["graph"]["nodes"], "gate")
  end
end
