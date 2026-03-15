defmodule AttractorPhoenix.LLMAdapters.Gemini do
  @moduledoc false

  @behaviour AttractorEx.LLM.ProviderAdapter

  alias AttractorEx.LLM.{Message, Request, Response, Usage}
  alias AttractorPhoenix.LLMAdapters.HTTP
  alias AttractorPhoenix.LLMSetup

  @base_url "https://generativelanguage.googleapis.com/v1beta/models"

  @impl true
  def complete(%Request{} = request) do
    with {:ok, api_key} <- api_key(),
         {:ok, body} <-
           HTTP.post_json(
             "#{@base_url}/#{request.model}:generateContent?key=#{URI.encode(api_key)}",
             [],
             build_payload(request)
           ) do
      {:ok, build_response(body)}
    end
    |> normalize_result()
  end

  defp api_key do
    case LLMSetup.provider_api_key("gemini") do
      nil -> {:error, "Gemini API key is missing. Visit Setup and save it first."}
      api_key -> {:ok, api_key}
    end
  end

  defp build_payload(%Request{} = request) do
    system_instruction =
      request.messages
      |> Enum.filter(&(&1.role in [:system, :developer]))
      |> Enum.map_join("\n\n", &Message.content_text(&1.content))
      |> blank_to_nil()

    contents =
      request.messages
      |> Enum.reject(&(&1.role in [:system, :developer]))
      |> Enum.map(&message_to_input/1)

    %{
      contents: contents,
      generationConfig:
        %{}
        |> maybe_put(:temperature, request.temperature)
        |> maybe_put(:topP, request.top_p)
        |> maybe_put(:maxOutputTokens, request.max_tokens)
        |> maybe_put(:stopSequences, empty_to_nil(request.stop_sequences))
    }
    |> maybe_put(
      :systemInstruction,
      if(system_instruction, do: %{parts: [%{text: system_instruction}]}, else: nil)
    )
  end

  defp message_to_input(%Message{} = message) do
    %{
      role: gemini_role(message.role),
      parts: [%{text: Message.content_text(message.content)}]
    }
  end

  defp gemini_role(:assistant), do: "model"
  defp gemini_role(_role), do: "user"

  defp build_response(body) do
    text =
      body["candidates"]
      |> List.wrap()
      |> List.first()
      |> case do
        %{"content" => %{"parts" => parts}} ->
          Enum.map_join(parts, "", &(&1["text"] || ""))

        _ ->
          ""
      end
      |> String.trim()

    %Response{
      text: text,
      finish_reason:
        to_string(get_in(body, ["candidates", Access.at(0), "finishReason"]) || "stop"),
      usage: %Usage{
        input_tokens: get_in(body, ["usageMetadata", "promptTokenCount"]) || 0,
        output_tokens: get_in(body, ["usageMetadata", "candidatesTokenCount"]) || 0,
        total_tokens: get_in(body, ["usageMetadata", "totalTokenCount"]) || 0
      },
      raw: body
    }
  end

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, _key, []), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)

  defp empty_to_nil([]), do: nil
  defp empty_to_nil(value), do: value

  defp blank_to_nil(value) do
    trimmed = value |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_result({:ok, %Response{} = response}), do: response
  defp normalize_result({:error, _reason} = error), do: error
end
