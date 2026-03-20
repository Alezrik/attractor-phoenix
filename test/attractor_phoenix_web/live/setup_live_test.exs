defmodule AttractorPhoenixWeb.SetupLiveTest do
  use AttractorPhoenixWeb.ConnCase

  alias AttractorPhoenix.LLMSetup

  import Phoenix.LiveViewTest

  setup do
    previous_fetcher = Application.get_env(:attractor_phoenix, :llm_model_fetcher)

    Application.put_env(:attractor_phoenix, :llm_model_fetcher, fn
      "openai", "openai-key" ->
        {:ok, [%{id: "gpt-5", provider: "openai", label: "gpt-5", raw: %{}}]}

      "anthropic", "anthropic-key" ->
        {:ok,
         [
           %{id: "claude-sonnet-4-5", provider: "anthropic", label: "claude-sonnet-4-5", raw: %{}}
         ]}

      "gemini", "gemini-key" ->
        {:ok, [%{id: "gemini-2.5-pro", provider: "gemini", label: "gemini-2.5-pro", raw: %{}}]}

      provider, _key ->
        {:error, "no fake models configured for #{provider}"}
    end)

    LLMSetup.reset()

    on_exit(fn ->
      restore_env(:attractor_phoenix, :llm_model_fetcher, previous_fetcher)
      LLMSetup.reset()
    end)

    :ok
  end

  test "setup page saves keys, fetches models, and stores a default", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/setup")

    assert html =~ "Provider control room"
    assert has_element?(view, "#setup-form")
    assert has_element?(view, "#default-model-form")
    assert has_element?(view, "#setup-summary-grid")
    assert has_element?(view, "#setup-proof-packet")
    assert html =~ "Provider readiness proof boundary"
    assert html =~ "not yet proven"
    refute html =~ "not yet proven by"
    assert html =~ "AttractorPhoenix.LLMSetup.get_settings()"

    view
    |> element("#setup-form")
    |> render_submit(%{
      "setup" => %{
        "openai" => "openai-key",
        "openai_mode" => "api",
        "openai_cli_command" => "codex exec --full-auto {prompt}",
        "anthropic" => "anthropic-key",
        "gemini" => "gemini-key",
        "action" => "refresh_models"
      }
    })

    assert render(view) =~ "Provider settings refreshed."
    assert render(view) =~ "gpt-5"
    assert render(view) =~ "claude-sonnet-4-5"
    assert render(view) =~ "gemini-2.5-pro"
    assert render(view) =~ "supported by"
    assert render(view) =~ "configured provider(s) ready for default routing"

    view
    |> element("#default-model-form")
    |> render_submit(%{"default" => %{"selection" => "anthropic::claude-sonnet-4-5"}})

    assert render(view) =~ "Default model updated."

    settings = LLMSetup.get_settings()
    assert settings.default_provider == "anthropic"
    assert settings.default_model == "claude-sonnet-4-5"
  end

  test "setup page supports openai cli mode and fallback model inventory", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/setup")

    view
    |> element("#setup-form")
    |> render_submit(%{
      "setup" => %{
        "openai" => "",
        "openai_mode" => "cli",
        "openai_cli_command" => "codex exec --full-auto {prompt}",
        "anthropic" => "",
        "gemini" => "",
        "action" => "refresh_models"
      }
    })

    assert render(view) =~ "Provider settings refreshed."
    assert render(view) =~ "Provider Credentials"
    assert render(view) =~ "codex-5.3"
    assert render(view) =~ "supported by"

    settings = LLMSetup.get_settings()
    assert settings.providers["openai"].mode == "cli"
    assert settings.providers["openai"].cli_command == "codex exec --full-auto {prompt}"
    assert Enum.any?(settings.providers["openai"].models, &(&1.id == "codex-5.3"))
  end

  test "setup upgrades the legacy codex cli template", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/setup")

    view
    |> element("#setup-form")
    |> render_submit(%{
      "setup" => %{
        "openai" => "",
        "openai_mode" => "cli",
        "openai_cli_command" => "codex --full-auto {prompt}",
        "anthropic" => "",
        "gemini" => "",
        "action" => "save_keys"
      }
    })

    settings = LLMSetup.get_settings()
    assert settings.providers["openai"].cli_command == "codex exec --full-auto {prompt}"
    assert render(view) =~ "codex exec --full-auto {prompt}"
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
