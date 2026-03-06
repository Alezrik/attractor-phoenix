defmodule AttractorPhoenixWeb.PipelineBuilderLiveTest do
  use AttractorPhoenixWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders live builder with hello world default graph", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Live graphical pipeline builder"
    assert html =~ "pipeline-builder"
    assert html =~ "echo hello world"
    assert html =~ "goodbye"
    assert html =~ "Run Pipeline"
  end

  test "runs pipeline from live form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    dot = """
    digraph attractor {
      start [shape=Mdiamond]
      hello [shape=parallelogram, tool_command="echo hello world"]
      done [shape=Msquare]
      start -> hello
      hello -> done
    }
    """

    params = %{
      "pipeline" => %{
        "dot" => dot,
        "context_json" => "{}"
      }
    }

    view
    |> element("#pipeline-runner-form")
    |> render_submit(params)

    assert has_element?(view, "#run-result")
    assert has_element?(view, "#command-output")
    assert render(view) =~ "hello world"
  end
end
