defmodule AttractorPhoenixWeb.PipelineBuilderLiveTest do
  use AttractorPhoenixWeb.ConnCase

  alias AttractorPhoenix.AttractorAPI

  import Phoenix.LiveViewTest

  test "renders live builder with hello world default graph", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/builder")

    assert html =~ "Pipeline Builder"
    assert html =~ "pipeline-builder"
    assert html =~ "echo hello world"
    assert html =~ "goodbye"
    assert html =~ "Run Pipeline"
  end

  test "submits pipeline through the HTTP API from the builder", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/builder")

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
    assert render(view) =~ "Run ID:"
  end

  test "dashboard renders API-backed pipeline data", %{conn: conn} do
    pipeline_id = "dashboard_test_#{System.unique_integer([:positive])}"

    assert {:ok, %{"pipeline_id" => ^pipeline_id}} =
             AttractorAPI.create_pipeline(sample_dot(), %{}, pipeline_id: pipeline_id)

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Real-time attractor-ex pipeline telemetry"
    assert html =~ pipeline_id
    assert html =~ "Open Builder"
  end

  defp sample_dot do
    """
    digraph attractor {
      start [shape=Mdiamond]
      hello [shape=parallelogram, tool_command="echo hello from dashboard"]
      done [shape=Msquare]
      start -> hello
      hello -> done
    }
    """
  end
end
