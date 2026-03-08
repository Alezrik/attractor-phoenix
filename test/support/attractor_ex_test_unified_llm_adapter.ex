defmodule AttractorExTest.UnifiedLLMAdapter do
  @moduledoc false

  alias AttractorEx.LLM.{Message, Request, Response, StreamEvent, Usage}

  def complete(%Request{} = request) do
    response_text =
      if request.metadata["json_mode"] do
        Jason.encode!(%{"provider" => request.provider, "model" => request.model})
      else
        "ok"
      end

    %Response{
      text: response_text,
      usage: %Usage{
        input_tokens: 100,
        output_tokens: 50,
        total_tokens: 150,
        reasoning_tokens: 20,
        cache_read_tokens: 7,
        cache_write_tokens: 3
      },
      finish_reason: "stop",
      raw: %{"request_snapshot" => snapshot(request)}
    }
  end

  def stream(%Request{} = request) do
    response_text =
      if request.metadata["json_mode"] do
        Jason.encode!(%{"provider" => request.provider, "streamed" => true})
      else
        "final"
      end

    [
      %StreamEvent{type: :stream_start},
      %StreamEvent{type: :text_delta, text: "chunk"},
      %StreamEvent{type: :reasoning_delta, reasoning: "thinking"},
      %StreamEvent{type: :tool_call, tool_call: %{"id" => "call-1", "name" => "echo"}},
      %StreamEvent{type: :tool_result, tool_result: %{"id" => "call-1", "output" => "done"}},
      %StreamEvent{
        type: :response,
        response: %Response{text: response_text, usage: %Usage{}, finish_reason: "stop"}
      },
      %StreamEvent{type: :stream_end, usage: %Usage{total_tokens: 1}},
      %StreamEvent{
        type: :error,
        error: {:simulated_error, request.provider || "unset"},
        raw: %{"request_snapshot" => snapshot(request)}
      }
    ]
  end

  defp snapshot(request) do
    %{
      "model" => request.model,
      "provider" => request.provider,
      "max_tokens" => request.max_tokens,
      "temperature" => request.temperature,
      "top_p" => request.top_p,
      "stop_sequences" => request.stop_sequences,
      "reasoning_effort" => request.reasoning_effort,
      "messages" =>
        Enum.map(request.messages, fn message ->
          %{
            "role" => message.role,
            "content" => Message.content_text(message.content),
            "tool_call_id" => message.tool_call_id,
            "name" => message.name
          }
        end),
      "response_format" => request.response_format,
      "provider_options" => request.provider_options,
      "metadata" => request.metadata
    }
  end
end
