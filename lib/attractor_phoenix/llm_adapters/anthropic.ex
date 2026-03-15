defmodule AttractorPhoenix.LLMAdapters.Anthropic do
  @moduledoc false

  @behaviour AttractorEx.LLM.ProviderAdapter

  alias AttractorEx.LLM.{Message, MessagePart, Request, Response, StreamEvent, Usage}
  alias AttractorPhoenix.LLMAdapters.HTTP
  alias AttractorPhoenix.LLMSetup

  @endpoint "https://api.anthropic.com/v1/messages"

  @impl true
  def complete(%Request{} = request) do
    with {:ok, api_key} <- api_key(),
         {:ok, body} <-
           HTTP.post_json(
             @endpoint,
             headers(api_key),
             build_payload(request),
             provider: "anthropic"
           ) do
      {:ok, build_response(body)}
    end
    |> normalize_result()
  end

  @impl true
  def stream(%Request{} = request) do
    with {:ok, api_key} <- api_key(),
         {:ok, %{body: body}} <-
           HTTP.post_json_stream(
             @endpoint,
             headers(api_key),
             Map.put(build_payload(request), :stream, true),
             provider: "anthropic"
           ) do
      parse_stream(body)
    end
  end

  defp api_key do
    case LLMSetup.provider_api_key("anthropic") do
      nil -> {:error, "Anthropic API key is missing. Visit Setup and save it first."}
      api_key -> {:ok, api_key}
    end
  end

  defp headers(api_key) do
    [
      {"x-api-key", api_key},
      {"anthropic-version", "2023-06-01"}
    ]
  end

  defp build_payload(%Request{} = request) do
    system =
      request.messages
      |> Enum.filter(&(&1.role in [:system, :developer]))
      |> Enum.flat_map(&anthropic_content/1)
      |> maybe_apply_cache(request.cache)

    messages =
      request.messages
      |> Enum.reject(&(&1.role in [:system, :developer]))
      |> Enum.map(&message_to_input(&1, request.cache))

    %{
      model: request.model,
      messages: messages,
      max_tokens: request.max_tokens || 8_192
    }
    |> maybe_put(:system, empty_to_nil(system))
    |> maybe_put(:temperature, request.temperature)
    |> maybe_put(:top_p, request.top_p)
    |> maybe_put(:stop_sequences, empty_to_nil(request.stop_sequences))
    |> maybe_put(:tools, build_tools(request.tools))
    |> maybe_put(:tool_choice, normalize_tool_choice(request.tool_choice))
    |> merge_response_format(request.response_format)
    |> Map.merge(stringify_map_keys(request.provider_options))
  end

  defp message_to_input(%Message{} = message, cache) do
    %{
      role: anthropic_role(message.role),
      content: message |> anthropic_content() |> maybe_apply_cache(cache)
    }
  end

  defp anthropic_content(%Message{content: content}) when is_list(content) do
    content
    |> Enum.map(&content_block/1)
    |> Enum.reject(&is_nil/1)
  end

  defp anthropic_content(%Message{content: content}) do
    [%{"type" => "text", "text" => to_string(content || "")}]
  end

  defp content_block(%MessagePart{type: :text, text: text}),
    do: %{"type" => "text", "text" => text || ""}

  defp content_block(%MessagePart{type: :thinking, text: text}),
    do: %{"type" => "thinking", "thinking" => text || ""}

  defp content_block(%MessagePart{type: :image, data: data}) do
    case data["base64"] || data[:base64] do
      nil ->
        %{
          "type" => "text",
          "text" => MessagePart.text_projection(%MessagePart{type: :image, data: data})
        }

      base64 ->
        %{
          "type" => "image",
          "source" => %{
            "type" => "base64",
            "media_type" => data["mime_type"] || data[:mime_type] || "image/png",
            "data" => base64
          }
        }
    end
  end

  defp content_block(%MessagePart{type: :tool_result, data: data}) do
    %{
      "type" => "tool_result",
      "tool_use_id" => data["tool_use_id"] || data[:tool_use_id],
      "content" => data["content"] || data[:content] || ""
    }
  end

  defp content_block(%MessagePart{type: :json, data: data}),
    do: %{"type" => "text", "text" => Jason.encode!(data || %{})}

  defp content_block(%MessagePart{} = part),
    do: %{"type" => "text", "text" => MessagePart.text_projection(part)}

  defp content_block(%{"type" => _type} = part), do: content_block(normalize_message_part(part))
  defp content_block(_part), do: nil

  defp build_tools([]), do: nil

  defp build_tools(tools) when is_list(tools) do
    Enum.map(tools, fn tool ->
      %{
        "name" => Map.get(tool, "name") || Map.get(tool, :name),
        "description" => Map.get(tool, "description") || Map.get(tool, :description),
        "input_schema" =>
          Map.get(tool, "parameters") || Map.get(tool, :parameters) ||
            %{"type" => "object", "properties" => %{}}
      }
    end)
  end

  defp build_tools(_tools), do: nil

  defp normalize_tool_choice(nil), do: nil
  defp normalize_tool_choice("auto"), do: %{"type" => "auto"}
  defp normalize_tool_choice("none"), do: %{"type" => "auto"}
  defp normalize_tool_choice("required"), do: %{"type" => "any"}
  defp normalize_tool_choice(value) when is_map(value), do: stringify_map_keys(value)
  defp normalize_tool_choice(_value), do: nil

  defp merge_response_format(payload, :json) do
    Map.put(payload, :response_format, %{"type" => "json"})
  end

  defp merge_response_format(payload, _response_format), do: payload

  defp maybe_apply_cache(blocks, nil), do: blocks

  defp maybe_apply_cache(blocks, cache) when is_list(blocks) and is_map(cache) do
    strategy = cache["strategy"] || cache[:strategy]

    if to_string(strategy) == "ephemeral" and blocks != [] do
      List.update_at(blocks, -1, fn block ->
        Map.put(block, "cache_control", %{"type" => "ephemeral"})
      end)
    else
      blocks
    end
  end

  defp maybe_apply_cache(blocks, _cache), do: blocks

  defp build_response(body) do
    text =
      body["content"]
      |> List.wrap()
      |> Enum.map_join("", fn item ->
        cond do
          item["type"] == "text" -> item["text"] || ""
          item["type"] == "thinking" -> ""
          true -> ""
        end
      end)
      |> String.trim()

    reasoning =
      body["content"]
      |> List.wrap()
      |> Enum.filter(&(&1["type"] == "thinking"))
      |> Enum.map_join("", &(&1["thinking"] || ""))
      |> blank_to_nil()

    %Response{
      id: body["id"],
      text: text,
      reasoning: reasoning,
      tool_calls:
        body["content"]
        |> List.wrap()
        |> Enum.map(&normalize_tool_call/1)
        |> Enum.reject(&is_nil/1),
      finish_reason: to_string(body["stop_reason"] || "stop"),
      usage: %Usage{
        input_tokens: get_in(body, ["usage", "input_tokens"]) || 0,
        output_tokens: get_in(body, ["usage", "output_tokens"]) || 0,
        total_tokens:
          (get_in(body, ["usage", "input_tokens"]) || 0) +
            (get_in(body, ["usage", "output_tokens"]) || 0),
        cache_read_tokens: get_in(body, ["usage", "cache_read_input_tokens"]) || 0,
        cache_write_tokens: get_in(body, ["usage", "cache_creation_input_tokens"]) || 0
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
    |> Enum.reject(&(&1 == ""))
    |> Enum.flat_map(fn payload ->
      case Jason.decode(payload) do
        {:ok, decoded} -> [decoded]
        _ -> []
      end
    end)
  end

  defp stream_events_from_payload(%{
         "type" => "content_block_delta",
         "delta" => %{"type" => "text_delta", "text" => text}
       }) do
    [%StreamEvent{type: :text_delta, text: text}]
  end

  defp stream_events_from_payload(%{
         "type" => "content_block_delta",
         "delta" => %{"type" => "thinking_delta", "thinking" => text}
       }) do
    [%StreamEvent{type: :reasoning_delta, reasoning: text}]
  end

  defp stream_events_from_payload(%{"type" => "content_block_start", "content_block" => block}) do
    case normalize_tool_call(block) do
      nil -> []
      tool_call -> [%StreamEvent{type: :tool_call, tool_call: tool_call}]
    end
  end

  defp stream_events_from_payload(%{"type" => "message_delta", "usage" => usage, "delta" => delta}) do
    [%StreamEvent{type: :stream_end, usage: build_usage(usage, delta)}]
  end

  defp stream_events_from_payload(%{"type" => "message_stop"}),
    do: [%StreamEvent{type: :stream_end}]

  defp stream_events_from_payload(%{"type" => "error", "error" => error}),
    do: [%StreamEvent{type: :error, error: error, raw: %{"error" => error}}]

  defp stream_events_from_payload(_payload), do: []

  defp normalize_tool_call(%{"type" => "tool_use"} = item) do
    %{
      "id" => item["id"],
      "name" => item["name"],
      "arguments" => Jason.encode!(item["input"] || %{})
    }
  end

  defp normalize_tool_call(_item), do: nil

  defp build_usage(usage, _delta) do
    %Usage{
      input_tokens: usage["input_tokens"] || 0,
      output_tokens: usage["output_tokens"] || 0,
      total_tokens: (usage["input_tokens"] || 0) + (usage["output_tokens"] || 0)
    }
  end

  defp anthropic_role(:assistant), do: "assistant"
  defp anthropic_role(_role), do: "user"

  defp normalize_message_part(part) do
    %MessagePart{
      type: normalize_part_type(part["type"]),
      text: part["text"] || part["thinking"],
      data: part["data"] || part["source"] || %{},
      mime_type: part["mime_type"]
    }
  end

  defp normalize_part_type("image"), do: :image
  defp normalize_part_type("tool_result"), do: :tool_result
  defp normalize_part_type("thinking"), do: :thinking
  defp normalize_part_type("json"), do: :json
  defp normalize_part_type(_type), do: :text

  defp maybe_put(payload, _key, nil), do: payload
  defp maybe_put(payload, _key, []), do: payload
  defp maybe_put(payload, key, value), do: Map.put(payload, key, value)

  defp empty_to_nil([]), do: nil
  defp empty_to_nil(value), do: value

  defp stringify_map_keys(map) when is_map(map) do
    Enum.into(map, %{}, fn {key, value} -> {to_string(key), value} end)
  end

  defp stringify_map_keys(value), do: value

  defp blank_to_nil(value) do
    trimmed = value |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_result({:ok, %Response{} = response}), do: response
  defp normalize_result({:error, _reason} = error), do: error
end
