defmodule AttractorPhoenixWeb.PipelineLibraryLiveTest do
  use AttractorPhoenixWeb.ConnCase

  alias AttractorPhoenix.PipelineLibrary

  import Phoenix.LiveViewTest

  setup do
    PipelineLibrary.reset()
    :ok
  end

  test "renders the library admin and creates a pipeline entry", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/library")

    assert html =~ "Pipeline Library"
    assert has_element?(view, "#library-page")
    assert has_element?(view, "#library-route-links")
    assert has_element?(view, "#library-form")
    assert html =~ "Save New Artifact"

    params = %{
      "library" => %{
        "name" => "Support Intake",
        "description" => "Routes support requests through intake",
        "dot" => sample_dot("echo support"),
        "context_json" => ~s({"team":"support"})
      }
    }

    view
    |> element("#library-form")
    |> render_submit(params)

    assert has_element?(view, "#library-entry-support-intake")
    assert has_element?(view, "#library-featured-entry")
    assert render(view) =~ "Reopen in Builder"
    assert render(view) =~ "Saved once"

    {:ok, entry} = PipelineLibrary.get_entry("support-intake")
    assert entry.name == "Support Intake"
  end

  test "library edit surface exposes stable artifact identity before reopening in builder", %{
    conn: conn
  } do
    {:ok, entry} =
      PipelineLibrary.create_entry(%{
        "name" => "Ops Runbook",
        "description" => "Operational response flow",
        "dot" => sample_dot("echo ops"),
        "context_json" => ~s({"team":"ops"})
      })

    {:ok, _view, html} = live(conn, ~p"/library")

    assert html =~ entry.name
    assert html =~ ~p"/builder?library=#{entry.id}"
    assert html =~ "Reopen in Builder"

    {:ok, _edit_view, edit_html} = live(conn, ~p"/library/#{entry.id}/edit")

    assert edit_html =~ "Update Existing Artifact"
    assert edit_html =~ "Artifact ID"
    assert edit_html =~ entry.id

    {:ok, _builder_view, builder_html} = live(conn, ~p"/builder?library=#{entry.id}")

    assert builder_html =~ "Ops Runbook"
    assert builder_html =~ "echo ops"
    assert builder_html =~ "Update Existing Artifact"
  end

  defp sample_dot(command) do
    """
    digraph attractor {
      start [shape=Mdiamond]
      work [shape=parallelogram, tool_command="#{command}"]
      done [shape=Msquare]
      start -> work
      work -> done
    }
    """
  end
end
