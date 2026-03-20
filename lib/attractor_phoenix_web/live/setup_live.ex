defmodule AttractorPhoenixWeb.SetupLive do
  use AttractorPhoenixWeb, :live_view

  alias AttractorPhoenix.LLMSetup
  alias AttractorPhoenix.TrustProof

  @impl true
  def mount(_params, _session, socket) do
    settings = LLMSetup.get_settings()

    {:ok,
     socket
     |> assign(
       page_title: "Setup",
       settings: settings,
       proof_packet: TrustProof.provider_health_record(settings),
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
             proof_packet: TrustProof.provider_health_record(settings),
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
             |> assign(
               settings: settings,
               proof_packet: TrustProof.provider_health_record(settings),
               setup_form: build_setup_form(settings),
               error: nil
             )
             |> assign(:default_form, build_default_form(settings))
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
               proof_packet: TrustProof.provider_health_record(settings),
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

  defp configured_provider_count(settings) do
    settings.providers
    |> Map.values()
    |> Enum.count(&(String.trim(&1.api_key) != "" or &1.mode == "cli"))
  end

  defp discovered_model_count(settings) do
    Enum.reduce(settings.providers, 0, fn {_provider, entry}, total ->
      total + length(entry.models)
    end)
  end

  defp provider_health_label(entry) do
    cond do
      entry.api_key == "" and entry.mode != "cli" -> "Needs key"
      entry.last_error != nil -> "Attention"
      entry.models == [] -> "Pending sync"
      true -> "Ready"
    end
  end

  defp provider_health_tone(entry) do
    cond do
      entry.api_key == "" and entry.mode != "cli" -> "setup-health-pill-missing"
      entry.last_error != nil -> "setup-health-pill-error"
      entry.models == [] -> "setup-health-pill-waiting"
      true -> "setup-health-pill-ready"
    end
  end

  defp provider_recency(entry) do
    entry.last_synced_at || "Never synced"
  end

  defp provider_key_status(entry) do
    cond do
      entry.mode == "cli" -> "CLI mode"
      entry.api_key == "" -> "Not saved"
      true -> "Saved"
    end
  end

  defp proof_status_tone(status) when status in ["ready", "fixed"],
    do: "bg-success/12 text-success"

  defp proof_status_tone("improved"), do: "bg-info/12 text-info"
  defp proof_status_tone("partial"), do: "bg-warning/12 text-warning"
  defp proof_status_tone("blocked"), do: "bg-error/12 text-error"
  defp proof_status_tone("unproven"), do: "bg-base-200 text-base-content/70"
  defp proof_status_tone(_status), do: "bg-base-200 text-base-content/70"

  defp support_phrase(record), do: TrustProof.support_phrase(record)

  defp proof_fields(record) do
    [
      {"Surface", record.surface},
      {"Scope", record.scope},
      {"Subject", record.subject},
      {"Status", record.status},
      {"Claim level", record.claim_level},
      {"Confidence basis", record.confidence_basis},
      {"Proof artifact", record.proof_artifact},
      {"Owner", record.owner},
      {"Timestamp", record.timestamp},
      {"Next action", record.next_action},
      {"Provider", record.provider},
      {"Readiness", record.readiness},
      {"Latency / cost / quality", record.latency_cost_quality_tradeoff}
    ]
  end
end
