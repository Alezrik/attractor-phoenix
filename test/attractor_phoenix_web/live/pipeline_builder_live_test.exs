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
    assert html =~ "Run via /run"
    assert html =~ "Submit via /pipelines"
    assert html =~ "Graph Contract"
    assert html =~ "node-prop-max-tokens"
    assert html =~ "node-prop-temperature"
    assert html =~ "node-prop-human-input"
    assert html =~ "node-prop-join-policy"
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
    assert render(view) =~ "Graph JSON"
    assert render(view) =~ "POST /run"
  end

  test "dashboard renders API-backed pipeline data", %{conn: conn} do
    pipeline_id = "dashboard_test_#{System.unique_integer([:positive])}"

    assert {:ok, %{"pipeline_id" => ^pipeline_id}} =
             AttractorAPI.create_pipeline(sample_dot(), %{}, pipeline_id: pipeline_id)

    {:ok, _view, html} = live(conn, ~p"/")

    assert html =~ "Real-time attractor-ex pipeline telemetry"
    assert html =~ pipeline_id
    assert html =~ "Open Builder"
    assert html =~ "POST /run"
    assert html =~ "/status?pipeline_id="
    assert html =~ "/answer"
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
