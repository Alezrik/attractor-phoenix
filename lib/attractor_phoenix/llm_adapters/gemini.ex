defmodule AttractorPhoenix.LLMAdapters.Gemini do
  @moduledoc false

  @behaviour AttractorEx.LLM.ProviderAdapter

  alias AttractorEx.LLM.{Message, MessagePart, Request, Response, StreamEvent, Usage}
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
             build_payload(request),
             provider: "gemini"
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
             "#{@base_url}/#{request.model}:streamGenerateContent?alt=sse&key=#{URI.encode(api_key)}",
             [],
             build_payload(request),
             provider: "gemini"
           ) do
      parse_stream(body)
    end
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
      |> Enum.flat_map(&gemini_parts/1)
      |> empty_to_nil()

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
        |> merge_response_format(request.response_format)
    }
    |> maybe_put(
      :systemInstruction,
      if(system_instruction, do: %{parts: system_instruction}, else: nil)
    )
    |> maybe_put(:tools, build_tools(request.tools))
    |> maybe_put(:toolConfig, normalize_tool_choice(request.tool_choice))
    |> maybe_put(:cachedContent, request.cache && (request.cache["key"] || request.cache[:key]))
    |> Map.merge(stringify_map_keys(request.provider_options))
  end

  defp message_to_input(%Message{} = message) do
    %{
      role: gemini_role(message.role),
      parts: gemini_parts(message)
    }
  end

  defp gemini_parts(%Message{content: content}) when is_list(content) do
    content
    |> Enum.map(&part_to_gemini/1)
    |> Enum.reject(&is_nil/1)
  end

  defp gemini_parts(%Message{content: content}) do
    [%{text: to_string(content || "")}]
  end

  defp part_to_gemini(%MessagePart{type: :text, text: text}), do: %{text: text || ""}
  defp part_to_gemini(%MessagePart{type: :thinking, text: text}), do: %{text: text || ""}

  defp part_to_gemini(%MessagePart{type: :image, data: data}) do
    cond do
      data["base64"] || data[:base64] ->
        %{
          inlineData: %{
            mimeType: data["mime_type"] || data[:mime_type] || "image/png",
            data: data["base64"] || data[:base64]
          }
        }

      data["url"] || data[:url] ->
        %{
          fileData: %{
            mimeType: data["mime_type"] || data[:mime_type] || "image/png",
            fileUri: data["url"] || data[:url]
          }
        }

      true ->
        %{text: MessagePart.text_projection(%MessagePart{type: :image, data: data})}
    end
  end

  defp part_to_gemini(%MessagePart{type: :document, data: data}) do
    %{
      fileData: %{
        mimeType: data["mime_type"] || data[:mime_type] || "application/octet-stream",
        fileUri: data["url"] || data[:url]
      }
    }
  end

  defp part_to_gemini(%MessagePart{type: :tool_call, data: data}) do
    %{
      functionCall: %{
        name: data["name"] || data[:name],
        args: data["arguments"] || data[:arguments] || %{}
      }
    }
  end

  defp part_to_gemini(%MessagePart{type: :tool_result, data: data}) do
    %{
      functionResponse: %{
        name: data["name"] || data[:name],
        response: data["response"] || data[:response] || %{}
      }
    }
  end

  defp part_to_gemini(%MessagePart{type: :json, data: data}),
    do: %{text: Jason.encode!(data || %{})}

  defp part_to_gemini(%MessagePart{} = part), do: %{text: MessagePart.text_projection(part)}
  defp part_to_gemini(%{"type" => _type} = part), do: part_to_gemini(normalize_message_part(part))
  defp part_to_gemini(_part), do: nil

  defp build_tools([]), do: nil

  defp build_tools(tools) when is_list(tools) do
    [
      %{
        functionDeclarations:
          Enum.map(tools, fn tool ->
            %{
              name: Map.get(tool, "name") || Map.get(tool, :name),
              description: Map.get(tool, "description") || Map.get(tool, :description),
              parameters:
                Map.get(tool, "parameters") || Map.get(tool, :parameters) ||
                  %{"type" => "object", "properties" => %{}}
            }
          end)
      }
    ]
  end

  defp build_tools(_tools), do: nil

  defp normalize_tool_choice(nil), do: nil
  defp normalize_tool_choice("auto"), do: %{functionCallingConfig: %{mode: "AUTO"}}
  defp normalize_tool_choice("required"), do: %{functionCallingConfig: %{mode: "ANY"}}
  defp normalize_tool_choice("none"), do: %{functionCallingConfig: %{mode: "NONE"}}
  defp normalize_tool_choice(value) when is_map(value), do: stringify_map_keys(value)
  defp normalize_tool_choice(_value), do: nil

  defp merge_response_format(config, :json),
    do: Map.put(config, :responseMimeType, "application/json")

  defp merge_response_format(config, %{type: :json_schema, schema: schema}) do
    config
    |> Map.put(:responseMimeType, "application/json")
    |> Map.put(:responseSchema, schema)
  end

  defp merge_response_format(config, _response_format), do: config

  defp build_response(body) do
    candidate = get_in(body, ["candidates", Access.at(0)]) || %{}
    parts = get_in(candidate, ["content", "parts"]) || []

    %Response{
      text:
        parts
        |> Enum.map_join("", fn part -> part["text"] || "" end)
        |> String.trim(),
      tool_calls:
        parts
        |> Enum.map(&normalize_tool_call/1)
        |> Enum.reject(&is_nil/1),
      finish_reason: to_string(candidate["finishReason"] || "stop"),
      usage: %Usage{
        input_tokens: get_in(body, ["usageMetadata", "promptTokenCount"]) || 0,
        output_tokens: get_in(body, ["usageMetadata", "candidatesTokenCount"]) || 0,
        total_tokens: get_in(body, ["usageMetadata", "totalTokenCount"]) || 0,
        cache_read_tokens: get_in(body, ["usageMetadata", "cachedContentTokenCount"]) || 0
      },
      raw: body
    }
  end

  defp parse_stream(body) when is_binary(body) do
    body
    |> sse_payloads()
    |> Enum.flat_map(fn payload ->
      response = build_response(payload)

      parts = get_in(payload, ["candidates", Access.at(0), "content", "parts"]) || []
      text = Enum.map_join(parts, "", &(&1["text"] || ""))
      tool_calls = Enum.map(parts, &normalize_tool_call/1) |> Enum.reject(&is_nil/1)

      [
        if(text != "", do: %StreamEvent{type: :text_delta, text: text}),
        Enum.map(tool_calls, &%StreamEvent{type: :tool_call, tool_call: &1}),
        %StreamEvent{type: :response, response: response},
        %StreamEvent{type: :stream_end, usage: response.usage}
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
    end)
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

  defp normalize_tool_call(%{"functionCall" => %{"name" => name} = function_call}) do
    %{
      "id" => function_call["id"] || name,
      "name" => name,
      "arguments" => Jason.encode!(function_call["args"] || %{})
    }
  end

  defp normalize_tool_call(_part), do: nil

  defp gemini_role(:assistant), do: "model"
  defp gemini_role(_role), do: "user"

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
  defp normalize_part_type("tool_call"), do: :tool_call
  defp normalize_part_type("tool_result"), do: :tool_result
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

  defp normalize_result({:ok, %Response{} = response}), do: response
  defp normalize_result({:error, _reason} = error), do: error
end
