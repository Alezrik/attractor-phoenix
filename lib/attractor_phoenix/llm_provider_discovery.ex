defmodule AttractorPhoenix.LLMProviderDiscovery do
  @moduledoc """
  Fetches available models for supported providers using provider-native model listing APIs.
  """

  @type model :: %{
          id: String.t(),
          provider: String.t(),
          label: String.t(),
          raw: map()
        }

  @spec fetch_models(String.t(), String.t()) :: {:ok, [model()]} | {:error, String.t()}
  def fetch_models(provider, api_key) when is_binary(provider) and is_binary(api_key) do
    case String.trim(provider) do
      "openai" -> fetch_openai_models(api_key)
      "anthropic" -> fetch_anthropic_models(api_key)
      "gemini" -> fetch_gemini_models(api_key)
      other -> {:error, "Unsupported provider: #{other}"}
    end
  end

  defp fetch_openai_models(api_key) do
    with {:ok, %{"data" => models}} <-
           get_json("https://api.openai.com/v1/models",
             headers: [{"authorization", "Bearer #{api_key}"}]
           ) do
      {:ok,
       models
       |> Enum.filter(&openai_generation_model?/1)
       |> Enum.map(&normalize_model("openai", &1["id"], &1))
       |> Enum.reject(&is_nil/1)
       |> sort_models()}
    end
  end

  defp fetch_anthropic_models(api_key) do
    with {:ok, %{"data" => models}} <-
           get_json("https://api.anthropic.com/v1/models",
             headers: [
               {"x-api-key", api_key},
               {"anthropic-version", "2023-06-01"}
             ]
           ) do
      {:ok,
       models
       |> Enum.filter(&anthropic_generation_model?/1)
       |> Enum.map(&normalize_model("anthropic", &1["id"], &1))
       |> Enum.reject(&is_nil/1)
       |> sort_models()}
    end
  end

  defp fetch_gemini_models(api_key) do
    url = "https://generativelanguage.googleapis.com/v1beta/models?key=#{URI.encode(api_key)}"

    with {:ok, %{"models" => models}} <- get_json(url) do
      {:ok,
       models
       |> Enum.filter(&gemini_generation_model?/1)
       |> Enum.map(fn model ->
         id =
           model["name"]
           |> to_string()
           |> String.replace_prefix("models/", "")

         normalize_model("gemini", id, model)
       end)
       |> Enum.reject(&is_nil/1)
       |> sort_models()}
    end
  end

  defp gemini_generation_model?(model) do
    methods = model["supportedGenerationMethods"] || []
    id = model["name"] |> to_string() |> String.replace_prefix("models/", "")

    String.contains?(id, "gemini") and
      Enum.any?(methods, &(&1 in ["generateContent", "streamGenerateContent"]))
  end

  defp anthropic_generation_model?(model) do
    model["id"]
    |> to_string()
    |> String.contains?("claude")
  end

  defp openai_generation_model?(model) do
    id = model["id"] |> to_string() |> String.downcase()

    allowed_prefixes = ["gpt-", "o1", "o3", "o4"]
    blocked_substrings = ["embed", "whisper", "tts", "dall-e", "realtime", "audio", "transcribe"]

    Enum.any?(allowed_prefixes, &String.starts_with?(id, &1)) and
      Enum.all?(blocked_substrings, &(not String.contains?(id, &1)))
  end

  defp normalize_model(_provider, id, _raw) when not is_binary(id), do: nil

  defp normalize_model(provider, id, raw) do
    trimmed_id = String.trim(id)

    if trimmed_id == "" do
      nil
    else
      %{
        id: trimmed_id,
        provider: provider,
        label: trimmed_id,
        raw: raw || %{}
      }
    end
  end

  defp sort_models(models) do
    Enum.sort_by(models, &String.downcase(&1.id))
  end

  defp get_json(url, opts \\ []) do
    req = Application.get_env(:attractor_phoenix, :llm_provider_req, Req)
    headers = Keyword.get(opts, :headers, [])

    case req.get(url, headers: headers) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 and is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: %{"error" => error}}} ->
        {:error, "HTTP #{status}: #{inspect(error)}"}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, exception} ->
        {:error, Exception.message(exception)}
    end
  end
end
