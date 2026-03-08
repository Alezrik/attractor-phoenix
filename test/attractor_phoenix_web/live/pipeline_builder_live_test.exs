defmodule AttractorPhoenixWeb.PipelineBuilderLiveTest do
  use AttractorPhoenixWeb.ConnCase

  alias AttractorExPhx.Client, as: AttractorAPI
  alias AttractorPhoenix.PipelineLibrary

  import Phoenix.LiveViewTest

  setup do
    PipelineLibrary.reset()
    :ok
  end

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

  test "saves the current builder pipeline to the library and reloads it by query param", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/builder")

    dot = """
    digraph attractor {
      start [shape=Mdiamond]
      archive [shape=parallelogram, tool_command="echo archived"]
      done [shape=Msquare]
      start -> archive
      archive -> done
    }
    """

    params = %{
      "pipeline" => %{
        "action" => "save_library",
        "dot" => dot,
        "context_json" => ~s({"dataset":"library"}),
        "library_name" => "Archive Pipeline",
        "library_description" => "Reusable archival flow"
      }
    }

    view
    |> element("#pipeline-runner-form")
    |> render_submit(params)

    assert render(view) =~ "Pipeline saved to the library."
    assert render(view) =~ "Loaded from library"

    {:ok, entry} = PipelineLibrary.get_entry("archive-pipeline")
    assert entry.description == "Reusable archival flow"

    {:ok, _reloaded_view, html} = live(conn, ~p"/builder?library=archive-pipeline")

    assert html =~ "Archive Pipeline"
    assert html =~ "Reusable archival flow"
    assert html =~ "echo archived"
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
