defmodule AttractorPhoenix.LLMAdapters.Anthropic do
  @moduledoc false

  @behaviour AttractorEx.LLM.ProviderAdapter

  alias AttractorEx.LLM.{Message, Request, Response, Usage}
  alias AttractorPhoenix.LLMAdapters.HTTP
  alias AttractorPhoenix.LLMSetup

  @endpoint "https://api.anthropic.com/v1/messages"

  @impl true
  def complete(%Request{} = request) do
    with {:ok, api_key} <- api_key(),
         {:ok, body} <-
           HTTP.post_json(
             @endpoint,
             [
               {"x-api-key", api_key},
               {"anthropic-version", "2023-06-01"}
             ],
             build_payload(request)
           ) do
      {:ok, build_response(body)}
    end
    |> normalize_result()
  end

  defp api_key do
    case LLMSetup.provider_api_key("anthropic") do
      nil -> {:error, "Anthropic API key is missing. Visit Setup and save it first."}
      api_key -> {:ok, api_key}
    end
  end

  defp build_payload(%Request{} = request) do
    system =
      request.messages
      |> Enum.filter(&(&1.role in [:system, :developer]))
      |> Enum.map_join("\n\n", &Message.content_text(&1.content))
      |> blank_to_nil()

    messages =
      request.messages
      |> Enum.reject(&(&1.role in [:system, :developer]))
      |> Enum.map(&message_to_input/1)

    %{
      model: request.model,
      messages: messages,
      max_tokens: request.max_tokens || 8_192
    }
    |> maybe_put(:system, system)
    |> maybe_put(:temperature, request.temperature)
    |> maybe_put(:top_p, request.top_p)
    |> maybe_put(:stop_sequences, empty_to_nil(request.stop_sequences))
  end

  defp message_to_input(%Message{} = message) do
    %{
      role: anthropic_role(message.role),
      content: Message.content_text(message.content)
    }
  end

  defp anthropic_role(:assistant), do: "assistant"
  defp anthropic_role(_role), do: "user"

  defp build_response(body) do
    text =
      body["content"]
      |> List.wrap()
      |> Enum.map_join("", fn item ->
        if item["type"] == "text", do: item["text"] || "", else: ""
      end)
      |> String.trim()

    %Response{
      id: body["id"],
      text: text,
      finish_reason: to_string(body["stop_reason"] || "stop"),
      usage: %Usage{
        input_tokens: get_in(body, ["usage", "input_tokens"]) || 0,
        output_tokens: get_in(body, ["usage", "output_tokens"]) || 0,
        total_tokens:
          (get_in(body, ["usage", "input_tokens"]) || 0) +
            (get_in(body, ["usage", "output_tokens"]) || 0)
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
