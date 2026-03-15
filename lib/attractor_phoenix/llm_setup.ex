defmodule AttractorPhoenix.LLMSetup do
  @moduledoc """
  File-backed storage for provider API keys, discovered models, and default model selection.
  """

  use GenServer

  alias AttractorPhoenix.LLMProviderDiscovery

  @providers ~w(openai anthropic gemini)
  @legacy_openai_cli_command "codex --full-auto {prompt}"
  @default_openai_cli_command "codex exec --full-auto {prompt}"

  @type provider_entry :: %{
          id: String.t(),
          api_key: String.t(),
          mode: String.t(),
          cli_command: String.t(),
          models: [map()],
          last_error: String.t() | nil,
          last_synced_at: String.t() | nil
        }

  @type settings :: %{
          providers: %{optional(String.t()) => provider_entry()},
          default_provider: String.t() | nil,
          default_model: String.t() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec get_settings() :: settings()
  def get_settings do
    GenServer.call(__MODULE__, :get_settings)
  end

  @spec save_api_keys(map()) :: {:ok, settings()} | {:error, String.t()}
  def save_api_keys(attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:save_api_keys, attrs})
  end

  @spec refresh_models() :: {:ok, settings()} | {:error, String.t()}
  def refresh_models do
    GenServer.call(__MODULE__, :refresh_models, 30_000)
  end

  @spec set_default(String.t(), String.t()) :: {:ok, settings()} | {:error, String.t()}
  def set_default(provider, model) when is_binary(provider) and is_binary(model) do
    GenServer.call(__MODULE__, {:set_default, provider, model})
  end

  @spec available_models() :: [map()]
  def available_models do
    get_settings()
    |> Map.get(:providers)
    |> Map.values()
    |> Enum.flat_map(& &1.models)
    |> Enum.sort_by(fn model -> {String.downcase(model.provider), String.downcase(model.id)} end)
  end

  @spec provider_api_key(String.t()) :: String.t() | nil
  def provider_api_key(provider) when is_binary(provider) do
    get_settings()
    |> Map.get(:providers, %{})
    |> Map.get(provider, %{})
    |> Map.get(:api_key)
    |> case do
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: nil, else: trimmed

      _ ->
        nil
    end
  end

  @spec provider_mode(String.t()) :: String.t()
  def provider_mode(provider) when is_binary(provider) do
    get_settings()
    |> Map.get(:providers, %{})
    |> Map.get(provider, %{})
    |> Map.get(:mode)
    |> normalize_mode()
  end

  @spec provider_cli_command(String.t()) :: String.t() | nil
  def provider_cli_command(provider) when is_binary(provider) do
    get_settings()
    |> Map.get(:providers, %{})
    |> Map.get(provider, %{})
    |> Map.get(:cli_command)
    |> case do
      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: nil, else: trimmed

      _ ->
        nil
    end
  end

  @spec default_selection() :: %{provider: String.t() | nil, model: String.t() | nil}
  def default_selection do
    settings = get_settings()
    %{provider: settings.default_provider, model: settings.default_model}
  end

  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(opts) do
    path = Keyword.get(opts, :path, storage_path())
    {:ok, %{path: path, settings: load_settings(path)}}
  end

  @impl true
  def handle_call(:get_settings, _from, state) do
    settings = normalize_runtime_settings(state.settings)
    {:reply, settings, %{state | settings: settings}}
  end

  def handle_call({:save_api_keys, attrs}, _from, state) do
    providers =
      Enum.reduce(@providers, state.settings.providers, fn provider, acc ->
        key =
          attrs
          |> Map.get(provider, Map.get(attrs, "#{provider}_api_key", ""))
          |> to_string()
          |> String.trim()

        mode =
          attrs
          |> Map.get("#{provider}_mode")
          |> normalize_mode()

        cli_command =
          attrs
          |> Map.get("#{provider}_cli_command", default_cli_command(provider))
          |> to_string()
          |> String.trim()
          |> then(&normalize_cli_command(provider, &1))

        Map.update!(acc, provider, fn entry ->
          %{
            entry
            | api_key: key,
              mode: mode,
              cli_command: cli_command
          }
        end)
      end)

    settings = %{state.settings | providers: providers}

    persist_and_reply(settings, state)
  end

  def handle_call(:refresh_models, _from, state) do
    settings =
      Enum.reduce(@providers, state.settings, fn provider, acc ->
        provider_entry = acc.providers[provider]

        cond do
          provider_entry.mode == "cli" ->
            put_in(acc, [:providers, provider], %{
              provider_entry
              | models: cli_fallback_models(provider),
                last_error: nil,
                last_synced_at: timestamp()
            })

          provider_entry.api_key == "" ->
            put_in(acc, [:providers, provider], %{provider_entry | models: [], last_error: nil})

          true ->
            case discovery_fetcher().(provider, provider_entry.api_key) do
              {:ok, models} ->
                put_in(acc, [:providers, provider], %{
                  provider_entry
                  | models: models,
                    last_error: nil,
                    last_synced_at: timestamp()
                })

              {:error, message} ->
                put_in(acc, [:providers, provider], %{
                  provider_entry
                  | models: [],
                    last_error: message,
                    last_synced_at: timestamp()
                })
            end
        end
      end)
      |> normalize_default_selection()

    persist_and_reply(settings, state)
  end

  def handle_call({:set_default, provider, model}, _from, state) do
    settings = state.settings

    if model_available?(settings, provider, model) do
      persist_and_reply(%{settings | default_provider: provider, default_model: model}, state)
    else
      {:reply, {:error, "Choose a discovered provider/model before saving the default."}, state}
    end
  end

  def handle_call(:reset, _from, state) do
    settings = default_settings()

    case persist_settings(state.path, settings) do
      :ok -> {:reply, :ok, %{state | settings: settings}}
      {:error, _reason} -> {:reply, :ok, %{state | settings: settings}}
    end
  end

  defp persist_and_reply(settings, state) do
    case persist_settings(state.path, settings) do
      :ok -> {:reply, {:ok, settings}, %{state | settings: settings}}
      {:error, reason} -> {:reply, {:error, inspect(reason)}, state}
    end
  end

  defp model_available?(settings, provider, model) do
    settings.providers
    |> Map.get(provider, %{})
    |> Map.get(:models, [])
    |> Enum.any?(&(&1.id == model))
  end

  defp normalize_default_selection(settings) do
    current =
      if settings.default_provider && settings.default_model &&
           model_available?(settings, settings.default_provider, settings.default_model) do
        settings
      else
        first_model = ordered_models(settings) |> List.first()

        case first_model do
          nil -> %{settings | default_provider: nil, default_model: nil}
          model -> %{settings | default_provider: model.provider, default_model: model.id}
        end
      end

    current
  end

  defp normalize_runtime_settings(settings) do
    providers =
      Map.new(settings.providers, fn {provider, entry} ->
        {provider, %{entry | cli_command: normalize_cli_command(provider, entry.cli_command)}}
      end)

    %{settings | providers: providers}
  end

  defp storage_path do
    Application.get_env(
      :attractor_phoenix,
      :llm_setup_path,
      Path.expand("../tmp/llm_setup.json", __DIR__)
    )
  end

  defp discovery_fetcher do
    Application.get_env(
      :attractor_phoenix,
      :llm_model_fetcher,
      &LLMProviderDiscovery.fetch_models/2
    )
  end

  defp load_settings(path) do
    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, settings} when is_map(settings) -> normalize_loaded_settings(settings)
          _ -> default_settings()
        end

      _ ->
        default_settings()
    end
  end

  defp normalize_loaded_settings(settings) do
    providers =
      Enum.reduce(@providers, %{}, fn provider, acc ->
        loaded = Map.get(settings["providers"] || %{}, provider, %{})

        Map.put(acc, provider, %{
          id: provider,
          api_key: Map.get(loaded, "api_key", ""),
          mode: normalize_mode(Map.get(loaded, "mode")),
          cli_command:
            loaded
            |> Map.get("cli_command", default_cli_command(provider))
            |> then(&normalize_cli_command(provider, &1)),
          models:
            Enum.map(Map.get(loaded, "models", []), fn model ->
              %{
                id: Map.get(model, "id", ""),
                provider: Map.get(model, "provider", provider),
                label: Map.get(model, "label", Map.get(model, "id", "")),
                raw: Map.get(model, "raw", %{})
              }
            end),
          last_error: Map.get(loaded, "last_error"),
          last_synced_at: Map.get(loaded, "last_synced_at")
        })
      end)

    %{
      providers: providers,
      default_provider: Map.get(settings, "default_provider"),
      default_model: Map.get(settings, "default_model")
    }
    |> normalize_default_selection()
  end

  defp persist_settings(path, settings) do
    payload = Jason.encode_to_iodata!(serialize_settings(settings), pretty: true)
    tmp_path = path <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(tmp_path, payload) do
      File.rename(tmp_path, path)
    end
  end

  defp serialize_settings(settings) do
    %{
      default_provider: settings.default_provider,
      default_model: settings.default_model,
      providers:
        settings.providers
        |> Enum.map(fn {provider, entry} ->
          {provider,
           %{
             api_key: entry.api_key,
             mode: entry.mode,
             cli_command: entry.cli_command,
             models: entry.models,
             last_error: entry.last_error,
             last_synced_at: entry.last_synced_at
           }}
        end)
        |> Map.new()
    }
  end

  defp default_settings do
    %{
      providers:
        Map.new(@providers, fn provider ->
          {provider,
           %{
             id: provider,
             api_key: "",
             mode: default_mode(provider),
             cli_command: default_cli_command(provider),
             models: [],
             last_error: nil,
             last_synced_at: nil
           }}
        end),
      default_provider: nil,
      default_model: nil
    }
  end

  defp ordered_models(settings) do
    @providers
    |> Enum.flat_map(fn provider ->
      settings.providers
      |> Map.get(provider, %{})
      |> Map.get(:models, [])
    end)
  end

  defp timestamp do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  defp normalize_mode("cli"), do: "cli"
  defp normalize_mode(_value), do: "api"

  defp default_mode(_provider), do: "api"

  defp default_cli_command("openai"), do: @default_openai_cli_command
  defp default_cli_command(_provider), do: "{prompt}"

  defp normalize_cli_command("openai", @legacy_openai_cli_command),
    do: @default_openai_cli_command

  defp normalize_cli_command(_provider, value), do: value

  defp cli_fallback_models("openai") do
    [
      %{id: "codex-5.3", provider: "openai", label: "codex-5.3", raw: %{"source" => "cli"}},
      %{id: "gpt-5", provider: "openai", label: "gpt-5", raw: %{"source" => "cli"}},
      %{id: "gpt-5-mini", provider: "openai", label: "gpt-5-mini", raw: %{"source" => "cli"}}
    ]
  end

  defp cli_fallback_models(_provider), do: []
end
