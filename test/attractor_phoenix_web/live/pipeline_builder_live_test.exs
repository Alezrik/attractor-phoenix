defmodule AttractorPhoenixWeb.PipelineBuilderLiveTest do
  use AttractorPhoenixWeb.ConnCase

  alias AttractorPhoenix.{LLMSetup, PipelineLibrary}

  import Phoenix.LiveViewTest

  setup do
    PipelineLibrary.reset()
    LLMSetup.reset()

    previous_llm = Application.get_env(:attractor_phoenix, :attractor_ex_llm)
    previous_fetcher = Application.get_env(:attractor_phoenix, :llm_model_fetcher)

    Application.put_env(:attractor_phoenix, :attractor_ex_llm,
      providers: %{"openai" => AttractorPhoenixTest.DotGeneratorAdapter},
      default_provider: "openai"
    )

    Application.put_env(:attractor_phoenix, :llm_model_fetcher, fn
      "openai", _api_key ->
        {:ok, [%{id: "gpt-test", provider: "openai", label: "gpt-test", raw: %{}}]}

      "anthropic", _api_key ->
        {:ok, [%{id: "claude-test", provider: "anthropic", label: "claude-test", raw: %{}}]}

      _provider, _api_key ->
        {:ok, []}
    end)

    {:ok, _settings} =
      LLMSetup.save_api_keys(%{"openai" => "test-key", "anthropic" => "test-key"})

    {:ok, _settings} = LLMSetup.refresh_models()
    {:ok, _settings} = LLMSetup.set_default("openai", "gpt-test")

    on_exit(fn ->
      restore_env(:attractor_phoenix, :attractor_ex_llm, previous_llm)
      restore_env(:attractor_phoenix, :llm_model_fetcher, previous_fetcher)
      LLMSetup.reset()
    end)

    :ok
  end

  test "renders live builder with hello world default graph", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/builder")

    assert html =~ "Pipeline Builder"
    assert html =~ "pipeline-builder"
    assert html =~ "Create with AI"
    assert html =~ "echo hello world"
    assert html =~ "goodbye"
    assert html =~ "Run via /run"
    assert html =~ "Submit via /pipelines"
    assert html =~ ">LLM<"
    assert html =~ "Graph Contract"
    assert html =~ "node-prop-max-tokens"
    assert html =~ "node-prop-temperature"
    assert html =~ "node-prop-human-input"
    assert html =~ "node-prop-join-policy"
    assert html =~ "node-prop-manager-stop-condition"
    assert html =~ "Edge Properties"
    assert html =~ "node-prop-add-edge"
    assert html =~ "node-prop-delete"
    assert html =~ "edge-prop-source"
    assert html =~ "edge-prop-save"
    assert html =~ "builder-diagnostics-panel"
    assert html =~ "builder-template-select"
    assert html =~ "builder-format-dot"
    assert html =~ "open-command-palette"
    assert html =~ "builder-command-palette"
    assert html =~ "builder-command-search"
    assert html =~ "builder-command-results"
    assert html =~ "builder-shortcut-cheatsheet"
    assert html =~ "builder-shortcuts-dialog"
  end

  test "builder node type selector covers all runtime node types", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/builder")

    for node_type <- [
          "start",
          "tool",
          "wait.human",
          "wait_for_human",
          "conditional",
          "parallel",
          "parallel.fan_in",
          "stack.manager_loop",
          "codergen",
          "exit"
        ] do
      assert html =~ ~s(value="#{node_type}")
    end
  end

  test "builder quick insert palette covers the primary runtime-backed shapes", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/builder")

    for button_id <- [
          "add-start",
          "add-tool",
          "add-llm",
          "add-wait-human",
          "add-conditional",
          "add-parallel",
          "add-parallel-fan-in",
          "add-stack-manager-loop",
          "add-end"
        ] do
      assert html =~ ~s(id="#{button_id}")
    end
  end

  test "builder exposes command palette actions and visible keyboard shortcuts", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/builder")

    assert html =~ "Command Palette"
    assert html =~ "Ctrl+K"
    assert html =~ "Shift+A"
    assert html =~ "Shift+R"
    assert html =~ "Open Palette"
    assert html =~ "Shortcuts"
    assert html =~ "Search actions and node inserts"
    assert html =~ "Quick add at cursor"
  end

  test "create route opens the prompt dialog and loads generated dot into the builder", %{
    conn: conn
  } do
    {:ok, view, html} = live(conn, ~p"/create")

    assert html =~ ~s(id="create-dialog")
    assert html =~ ~s(id="create-progress-panel")
    assert html =~ "Describe the workflow in English"

    view
    |> element("#create-pipeline-form")
    |> render_submit(%{
      "create" => %{
        "prompt" => "Create a planning pipeline with an exit node",
        "provider" => "openai",
        "model" => "gpt-test"
      }
    })

    assert_patch(view, ~p"/builder")
    assert has_element?(view, "#pipeline-dot")
    assert render(view) =~ "Generated DOT loaded into the builder."
    assert render(view) =~ "digraph generated_pipeline"
  end

  test "create route shows discovered providers and models", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/create")

    assert html =~ ~s(id="create-provider")
    assert html =~ ~s(id="create-model")
    assert html =~ "Openai"
    assert html =~ "gpt-test"
    refute html =~ "Anthropic / claude-test"
  end

  test "create route accepts noisy model output as long as it contains one valid graph", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/create")

    view
    |> element("#create-pipeline-form")
    |> render_submit(%{
      "create" => %{
        "prompt" => "noisy output please",
        "provider" => "openai",
        "model" => "gpt-test"
      }
    })

    assert_patch(view, ~p"/builder")
    assert render(view) =~ "Generated DOT loaded into the builder."
    assert render(view) =~ "digraph generated_pipeline"
    refute render(view) =~ "Codex session starting"
  end

  test "create route filters models to the selected provider", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/create")

    html =
      view
      |> element("#create-pipeline-form")
      |> render_change(%{
        "create" => %{
          "prompt" => "Create a review workflow",
          "provider" => "anthropic",
          "model" => "gpt-test"
        }
      })

    assert html =~ "Anthropic / claude-test"
    refute html =~ "Openai / gpt-test"
  end

  test "create route surfaces generator errors", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/create")

    view
    |> element("#create-pipeline-form")
    |> render_submit(%{
      "create" => %{
        "prompt" => "broken output please",
        "provider" => "openai",
        "model" => "gpt-test"
      }
    })

    assert has_element?(view, "#create-dialog-error")
    assert render(view) =~ "Generated DOT could not be parsed"
  end

  test "create route stays connected when generator crashes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/create")

    view
    |> element("#create-pipeline-form")
    |> render_submit(%{
      "create" => %{
        "prompt" => "explode output please",
        "provider" => "openai",
        "model" => "gpt-test"
      }
    })

    assert has_element?(view, "#create-dialog-error")
    assert has_element?(view, "#create-dialog")
    assert render(view) =~ "DOT generation crashed"
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

  test "builder run result links to the dedicated run detail page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/builder")

    params = %{
      "pipeline" => %{
        "dot" => sample_dot(),
        "context_json" => "{}"
      }
    }

    view
    |> element("#pipeline-runner-form")
    |> render_submit(params)

    assert has_element?(view, "#open-run-detail")
    assert render(view) =~ "/runs/"
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

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
