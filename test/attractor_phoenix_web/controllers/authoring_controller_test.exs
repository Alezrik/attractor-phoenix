defmodule AttractorPhoenixWeb.AuthoringControllerTest do
  use AttractorPhoenixWeb.ConnCase, async: true

  test "lists authoring templates", %{conn: conn} do
    conn = get(conn, ~p"/api/authoring/templates")

    assert %{"templates" => templates} = json_response(conn, 200)
    assert Enum.any?(templates, &(&1["id"] == "hello_world"))
    assert Enum.any?(templates, &(&1["id"] == "approval_gate"))
  end

  test "analyzes dot through the authoring api", %{conn: conn} do
    dot = """
    digraph attractor {
      start [shape=Mdiamond]
      done [shape=Msquare]
      start -> done
    }
    """

    conn = post(conn, ~p"/api/authoring/analyze", %{"dot" => dot})

    assert %{"dot" => canonical_dot, "graph" => %{"nodes" => nodes}, "diagnostics" => []} =
             json_response(conn, 200)

    assert canonical_dot =~ ~s(start [shape="Mdiamond", label="start"])
    assert nodes["done"]["type"] == "exit"
  end

  test "surfaces parse failures from the authoring api", %{conn: conn} do
    conn = post(conn, ~p"/api/authoring/analyze", %{"dot" => "not dot"})

    assert %{"error" => error, "diagnostics" => [%{"code" => "parse_error"}]} =
             json_response(conn, 422)

    assert error =~ "Invalid DOT input"
  end

  test "applies builder transforms through the authoring api", %{conn: conn} do
    dot = """
    digraph attractor {
      work [shape=parallelogram, tool_command="echo hi"]
      done [shape=Msquare]
      work -> done
    }
    """

    conn =
      post(conn, ~p"/api/authoring/transform", %{
        "action" => "apply_fix",
        "dot" => dot,
        "fix_id" => "add_start_node"
      })

    assert %{"graph" => %{"nodes" => nodes}, "dot" => canonical_dot} = json_response(conn, 200)
    assert nodes["start"]["type"] == "start"
    assert canonical_dot =~ ~s(start [shape="Mdiamond", label="start"])
  end
end
