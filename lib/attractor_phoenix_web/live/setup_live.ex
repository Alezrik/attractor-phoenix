defmodule AttractorPhoenixWeb.SetupLive do
  use AttractorPhoenixWeb, :live_view

  alias AttractorPhoenix.LLMSetup

  @impl true
  def mount(_params, _session, socket) do
    settings = LLMSetup.get_settings()

    {:ok,
     socket
     |> assign(
       page_title: "Setup",
       settings: settings,
       setup_form: build_setup_form(settings),
       default_form: build_default_form(settings),
       error: nil
     )}
  end

  @impl true
  def handle_event("submit_setup", %{"setup" => params}, socket) do
    case Map.get(params, "action", "save_keys") do
      "refresh_models" ->
        with {:ok, _settings} <- LLMSetup.save_api_keys(params),
             {:ok, settings} <- LLMSetup.refresh_models() do
          {:noreply,
           socket
           |> assign(
             settings: settings,
             setup_form: build_setup_form(settings),
             default_form: build_default_form(settings),
             error: nil
           )
           |> put_flash(:info, "Provider settings refreshed.")}
        else
          {:error, message} ->
            {:noreply, assign(socket, error: message)}
        end

      _ ->
        case LLMSetup.save_api_keys(params) do
          {:ok, settings} ->
            {:noreply,
             socket
             |> assign(settings: settings, setup_form: build_setup_form(settings), error: nil)
             |> put_flash(:info, "API keys saved.")}

          {:error, message} ->
            {:noreply, assign(socket, error: message)}
        end
    end
  end

  def handle_event("save_default", %{"default" => %{"selection" => selection}}, socket) do
    case parse_selection(selection) do
      {:ok, provider, model} ->
        case LLMSetup.set_default(provider, model) do
          {:ok, settings} ->
            {:noreply,
             socket
             |> assign(
               settings: settings,
               setup_form: build_setup_form(settings),
               default_form: build_default_form(settings),
               error: nil
             )
             |> put_flash(:info, "Default model updated.")}

          {:error, message} ->
            {:noreply, assign(socket, error: message)}
        end

      :error ->
        {:noreply, assign(socket, error: "Select a discovered model before saving the default.")}
    end
  end

  defp build_setup_form(settings) do
    providers = settings.providers

    to_form(
      %{
        "openai" => providers["openai"].api_key,
        "openai_mode" => providers["openai"].mode,
        "openai_cli_command" => providers["openai"].cli_command,
        "anthropic" => providers["anthropic"].api_key,
        "gemini" => providers["gemini"].api_key
      },
      as: :setup
    )
  end

  defp build_default_form(settings) do
    selection =
      case {settings.default_provider, settings.default_model} do
        {provider, model} when is_binary(provider) and is_binary(model) -> "#{provider}::#{model}"
        _ -> ""
      end

    to_form(%{"selection" => selection}, as: :default)
  end

  defp parse_selection(selection) when is_binary(selection) do
    case String.split(selection, "::", parts: 2) do
      [provider, model] when provider != "" and model != "" -> {:ok, provider, model}
      _ -> :error
    end
  end

  defp parse_selection(_selection), do: :error
end
