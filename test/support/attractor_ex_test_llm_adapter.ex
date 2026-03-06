defmodule AttractorExTest.LLMAdapter do
  @moduledoc false

  alias AttractorEx.LLM.{Request, Response, StreamEvent, Usage}

  def complete(%Request{} = request) do
    text_part =
      request.messages
      |> List.first()
      |> case do
        nil -> ""
        message -> message.content
      end

    %Response{
      text: "provider=#{request.provider} model=#{request.model} prompt=#{text_part}",
      usage: %Usage{input_tokens: 10, output_tokens: 5, total_tokens: 15, reasoning_tokens: 2},
      finish_reason: "stop",
      raw: %{"ok" => true}
    }
  end

  def stream(%Request{} = request) do
    [
      %StreamEvent{type: :stream_start},
      %StreamEvent{type: :text_delta, text: "provider=#{request.provider}"}
    ]
  end
end
