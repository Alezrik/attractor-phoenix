defmodule AttractorPhoenix.LLMAdapters.OpenAI do
  @moduledoc false

  @behaviour AttractorEx.LLM.ProviderAdapter

  alias AttractorEx.LLM.{Message, MessagePart, Request, Response, StreamEvent, Usage}
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
             build_payload(request),
             provider: "openai"
           ) do
      build_response(body)
    end
  end

  @impl true
  def stream(%Request{} = request) do
    with {:ok, api_key} <- api_key(),
         {:ok, %{body: body}} <-
           HTTP.post_json_stream(
             @endpoint,
             [{"authorization", "Bearer #{api_key}"}],
             Map.put(build_payload(request), :stream, true),
             provider: "openai"
           ) do
      parse_stream(body)
    end
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

    base_payload =
      %{
        model: request.model,
        input:
          request.messages
          |> Enum.reject(&(&1.role in [:system, :developer]))
          |> Enum.flat_map(&message_to_input/1)
      }
      |> maybe_put(:instructions, instructions)
      |> maybe_put(:max_output_tokens, request.max_tokens)
      |> maybe_put(:temperature, supported_temperature(request.model, request.temperature))
      |> maybe_put(:top_p, request.top_p)
      |> maybe_put(:stop, empty_to_nil(request.stop_sequences))
      |> maybe_put(:tools, build_tools(request.tools))
      |> maybe_put(:tool_choice, normalize_tool_choice(request.tool_choice))
      |> merge_response_format(request.response_format)
      |> merge_reasoning(request.reasoning_effort)
      |> merge_cache(request.cache)

    Map.merge(base_payload, stringify_map_keys(request.provider_options))
  end

  defp message_to_input(%Message{role: :tool, tool_call_id: tool_call_id} = message)
       when is_binary(tool_call_id) and tool_call_id != "" do
    [
      %{
        type: "function_call_output",
        call_id: tool_call_id,
        output: Message.content_text(message.content)
      }
    ]
  end

  defp message_to_input(%Message{} = message) do
    [
      %{
        type: "message",
        role: openai_role(message.role),
        content: message_content(message)
      }
    ]
  end

  defp message_content(%Message{content: content, role: role}) when is_list(content) do
    content
    |> Enum.map(&message_part_to_content(role, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp message_content(%Message{role: role, content: content}) do
    [%{type: text_content_type(role), text: to_string(content || "")}]
  end

  defp message_part_to_content(role, %MessagePart{type: :text, text: text}),
    do: %{type: text_content_type(role), text: text || ""}

  defp message_part_to_content(_role, %MessagePart{type: :thinking, text: text}),
    do: %{type: "input_text", text: text || ""}

  defp message_part_to_content(_role, %MessagePart{type: :image, data: data}) do
    %{
      type: "input_image",
      image_url: data["url"] || data[:url],
      detail: data["detail"] || data[:detail] || "auto"
    }
    |> compact_map()
  end

  defp message_part_to_content(_role, %MessagePart{type: :document, data: data}) do
    %{
      type: "input_file",
      file_url: data["url"] || data[:url],
      filename: data["filename"] || data[:filename]
    }
    |> compact_map()
  end

  defp message_part_to_content(_role, %MessagePart{type: :json, data: data}) do
    %{type: "input_text", text: Jason.encode!(data || %{})}
  end

  defp message_part_to_content(_role, %MessagePart{} = part) do
    %{type: "input_text", text: MessagePart.text_projection(part)}
  end

  defp message_part_to_content(role, %{"type" => _type} = part) do
    message_part_to_content(role, normalize_message_part(part))
  end

  defp message_part_to_content(_role, _part), do: nil

  defp build_tools([]), do: nil

  defp build_tools(tools) when is_list(tools) do
    Enum.map(tools, fn
      %{"type" => "function"} = tool ->
        tool

      %{type: "function"} = tool ->
        stringify_map_keys(tool)

      %{"name" => name} = tool ->
        %{
          "type" => "function",
          "name" => name,
          "description" => tool["description"],
          "parameters" => tool["parameters"] || %{"type" => "object", "properties" => %{}}
        }

      %{name: name} = tool ->
        %{
          "type" => "function",
          "name" => name,
          "description" => Map.get(tool, :description),
          "parameters" => Map.get(tool, :parameters) || %{"type" => "object", "properties" => %{}}
        }
    end)
  end

  defp build_tools(_tools), do: nil

  defp build_response(body) do
    %Response{
      id: body["id"],
      text: extract_text(body),
      reasoning: extract_reasoning(body),
      tool_calls: extract_tool_calls(body),
      finish_reason: to_string(body["status"] || "stop"),
      usage: %Usage{
        input_tokens: get_in(body, ["usage", "input_tokens"]) || 0,
        output_tokens: get_in(body, ["usage", "output_tokens"]) || 0,
        total_tokens: get_in(body, ["usage", "total_tokens"]) || 0,
        reasoning_tokens:
          get_in(body, ["usage", "output_tokens_details", "reasoning_tokens"]) || 0,
        cache_read_tokens: get_in(body, ["usage", "input_tokens_details", "cached_tokens"]) || 0
      },
      raw: body
    }
  end

  defp parse_stream(body) when is_binary(body) do
    body
    |> sse_payloads()
    |> Enum.flat_map(&stream_events_from_payload/1)
  end

  defp sse_payloads(body) do
    body
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.starts_with?(&1, "data:"))
    |> Enum.map(&String.trim_leading(&1, "data:"))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 in ["", "[DONE]"]))
    |> Enum.flat_map(fn payload ->
      case Jason.decode(payload) do
        {:ok, decoded} -> [decoded]
        _ -> []
      end
    end)
  end

  defp stream_events_from_payload(%{"type" => "response.output_text.delta"} = payload) do
    [%StreamEvent{type: :text_delta, text: payload["delta"] || payload["text"] || ""}]
  end

  defp stream_events_from_payload(%{"type" => "response.reasoning.delta"} = payload) do
    [%StreamEvent{type: :reasoning_delta, reasoning: payload["delta"] || ""}]
  end

  defp stream_events_from_payload(%{"type" => "response.reasoning_summary.delta"} = payload) do
    [%StreamEvent{type: :reasoning_delta, reasoning: payload["delta"] || ""}]
  end

  defp stream_events_from_payload(%{"type" => "response.output_item.added", "item" => item}) do
    case normalize_tool_call(item) do
      nil -> []
      tool_call -> [%StreamEvent{type: :tool_call, tool_call: tool_call}]
    end
  end

  defp stream_events_from_payload(%{"type" => "response.completed", "response" => response}) do
    [
      %StreamEvent{type: :response, response: build_response(response)},
      %StreamEvent{type: :stream_end, usage: build_response(response).usage}
    ]
  end

  defp stream_events_from_payload(%{"type" => "response.failed", "error" => error}) do
    [%StreamEvent{type: :error, error: error, raw: %{"error" => error}}]
  end

  defp stream_events_from_payload(_payload), do: []

  defp extract_text(%{"output_text" => text}) when is_binary(text), do: String.trim(text)

  defp extract_text(%{"output" => output}) when is_list(output) do
    output
    |> Enum.flat_map(fn
      %{"type" => "message", "content" => content} -> List.wrap(content)
      _ -> []
    end)
    |> Enum.map_join("", fn
      %{"text" => text} when is_binary(text) -> text
      %{"text" => %{"value" => value}} when is_binary(value) -> value
      _ -> ""
    end)
    |> String.trim()
  end

  defp extract_text(_body), do: ""

  defp extract_reasoning(%{"output" => output}) when is_list(output) do
    output
    |> Enum.filter(&(&1["type"] == "reasoning"))
    |> Enum.map_join("", fn item ->
      item
      |> Map.get("summary", [])
      |> List.wrap()
      |> Enum.map_join("", fn summary ->
        summary["text"] || summary["content"] || ""
      end)
    end)
    |> blank_to_nil()
  end

  defp extract_reasoning(_body), do: nil

  defp extract_tool_calls(%{"output" => output}) when is_list(output) do
    output
    |> Enum.map(&normalize_tool_call/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_tool_calls(_body), do: []

  defp normalize_tool_call(%{"type" => "function_call"} = item) do
    %{
      "id" => item["call_id"] || item["id"],
      "name" => item["name"],
      "arguments" => item["arguments"] || item["input"] || "{}"
    }
  end

  defp normalize_tool_call(_item), do: nil

  defp normalize_tool_choice(nil), do: nil
  defp normalize_tool_choice(value) when is_binary(value), do: value
  defp normalize_tool_choice(value) when is_map(value), do: stringify_map_keys(value)
  defp normalize_tool_choice(_value), do: nil

  defp merge_response_format(payload, :json) do
    Map.put(payload, :text, %{format: %{type: "json_object"}})
  end

  defp merge_response_format(payload, %{type: :json_schema, schema: schema}) do
    Map.put(payload, :text, %{format: %{type: "json_schema", schema: schema}})
  end

  defp merge_response_format(payload, _response_format), do: payload

  defp merge_reasoning(payload, nil), do: payload

  defp merge_reasoning(payload, effort) do
    Map.put(payload, :reasoning, %{effort: effort})
  end

  defp merge_cache(payload, nil), do: payload

  defp merge_cache(payload, cache) when is_map(cache) do
    cache_key = cache["key"] || cache[:key]
    cache_ttl = cache["ttl_seconds"] || cache[:ttl_seconds]

    payload
    |> maybe_put(:prompt_cache_key, cache_key)
    |> maybe_put(:prompt_cache_ttl_seconds, cache_ttl)
  end

  defp merge_cache(payload, _cache), do: payload

  defp openai_role(role) when role in [:user, :assistant], do: Atom.to_string(role)
  defp openai_role(:tool), do: "user"
  defp openai_role(_role), do: "user"

  defp text_content_type(:assistant), do: "output_text"
  defp text_content_type(_role), do: "input_text"

  defp normalize_message_part(part) do
    %MessagePart{
      type: normalize_part_type(part["type"]),
      text: part["text"],
      data: part["data"] || %{},
      mime_type: part["mime_type"]
    }
  end

  defp normalize_part_type("image"), do: :image
  defp normalize_part_type("document"), do: :document
  defp normalize_part_type("json"), do: :json
  defp normalize_part_type("thinking"), do: :thinking
  defp normalize_part_type(_type), do: :text

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

  defp compact_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp stringify_map_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp stringify_map_keys(value), do: value

  defp empty_to_nil([]), do: nil
  defp empty_to_nil(value), do: value

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    trimmed = value |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end
end
