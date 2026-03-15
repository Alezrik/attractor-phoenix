defmodule AttractorPhoenix.LLMAdapters.OpenAI do
  @moduledoc false

  @behaviour AttractorEx.LLM.ProviderAdapter

  alias AttractorEx.LLM.{Message, Request, Response, Usage}
  alias AttractorPhoenix.LLMAdapters.HTTP
  alias AttractorPhoenix.LLMSetup

  @endpoint "https://api.openai.com/v1/responses"

  @impl true
  def complete(%Request{} = request) do
    with {:ok, api_key} <- api_key(),
         {:ok, body} <-
           HTTP.post_json(
             @endpoint,
             [{"authorization", "Bearer #{api_key}"}],
             build_payload(request)
           ) do
      {:ok, build_response(body)}
    end
    |> normalize_result()
  end

  defp api_key do
    case LLMSetup.provider_api_key("openai") do
      nil -> {:error, "OpenAI API key is missing. Visit Setup and save it first."}
      api_key -> {:ok, api_key}
    end
  end

  defp build_payload(%Request{} = request) do
    instructions =
      request.messages
      |> Enum.filter(&(&1.role in [:system, :developer]))
      |> Enum.map_join("\n\n", &Message.content_text(&1.content))
      |> blank_to_nil()

    payload =
      %{
        model: request.model,
        input:
          request.messages
          |> Enum.reject(&(&1.role in [:system, :developer]))
          |> Enum.map(&message_to_input/1)
      }
      |> maybe_put(:instructions, instructions)
      |> maybe_put(:max_output_tokens, request.max_tokens)
      |> maybe_put(:temperature, supported_temperature(request.model, request.temperature))
      |> maybe_put(:top_p, request.top_p)
      |> maybe_put(:stop, empty_to_nil(request.stop_sequences))

    case blank_to_nil(request.reasoning_effort) do
      nil -> payload
      effort -> Map.put(payload, :reasoning, %{effort: effort})
    end
  end

  defp message_to_input(%Message{} = message) do
    %{
      type: "message",
      role: openai_role(message.role),
      content: [message_content(message)]
    }
  end

  defp message_content(%Message{role: :assistant} = message) do
    %{type: "output_text", text: Message.content_text(message.content)}
  end

  defp message_content(%Message{} = message) do
    %{type: "input_text", text: Message.content_text(message.content)}
  end

  defp openai_role(role) when role in [:user, :assistant], do: Atom.to_string(role)
  defp openai_role(_role), do: "user"

  defp build_response(body) do
    %Response{
      id: body["id"],
      text: extract_text(body),
      finish_reason: to_string(body["status"] || "stop"),
      usage: %Usage{
        input_tokens: get_in(body, ["usage", "input_tokens"]) || 0,
        output_tokens: get_in(body, ["usage", "output_tokens"]) || 0,
        total_tokens: get_in(body, ["usage", "total_tokens"]) || 0
      },
      raw: body
    }
  end

  defp extract_text(%{"output_text" => text}) when is_binary(text), do: String.trim(text)

  defp extract_text(%{"output" => output}) when is_list(output) do
    output
    |> Enum.flat_map(fn item ->
      if item["type"] == "message" do
        List.wrap(item["content"])
      else
        []
      end
    end)
    |> Enum.map_join("", fn content ->
      cond do
        is_binary(content["text"]) ->
          content["text"]

        is_map(content["text"]) and is_binary(content["text"]["value"]) ->
          content["text"]["value"]

        true ->
          ""
      end
    end)
    |> String.trim()
  end

  defp extract_text(_body), do: ""

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, _key, []), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)

  defp supported_temperature(model, temperature) do
    if openai_temperature_supported?(model), do: temperature, else: nil
  end

  defp openai_temperature_supported?(model) when is_binary(model) do
    normalized = String.downcase(String.trim(model))

    not (String.contains?(normalized, "codex") or
           String.starts_with?(normalized, "gpt-5") or
           String.starts_with?(normalized, "o1") or
           String.starts_with?(normalized, "o3") or
           String.starts_with?(normalized, "o4"))
  end

  defp openai_temperature_supported?(_model), do: true

  defp empty_to_nil([]), do: nil
  defp empty_to_nil(value), do: value

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    trimmed = value |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_result({:ok, %Response{} = response}), do: response
  defp normalize_result({:error, _reason} = error), do: error
end
