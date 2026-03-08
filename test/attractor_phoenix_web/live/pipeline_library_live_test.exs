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
    assert html =~ "New Library Pipeline"
    assert has_element?(view, "#library-form")

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
    assert render(view) =~ "Load in Builder"

    {:ok, entry} = PipelineLibrary.get_entry("support-intake")
    assert entry.name == "Support Intake"
  end

  test "loads an existing library pipeline into the builder from the admin page", %{conn: conn} do
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

    {:ok, _builder_view, builder_html} = live(conn, ~p"/builder?library=#{entry.id}")

    assert builder_html =~ "Loaded from library"
    assert builder_html =~ "Ops Runbook"
    assert builder_html =~ "echo ops"
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
