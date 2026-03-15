defmodule AttractorExTest.RetryLLMAdapter do
  @moduledoc false

  alias AttractorEx.LLM.{Error, Request, Response, StreamEvent, Usage}

  def complete(%Request{} = request) do
    key = {__MODULE__, request.metadata["attempt_key"] || "complete"}
    attempt = Process.get(key, 0) + 1
    Process.put(key, attempt)

    if attempt < 3 do
      {:error,
       %Error{
         type: :rate_limited,
         provider: request.provider,
         message: "retry later",
         retryable: true,
         retry_after_ms: 0
       }}
    else
      %Response{text: "retried", usage: %Usage{total_tokens: 1}, finish_reason: "stop"}
    end
  end

  def stream(%Request{} = request) do
    key = {__MODULE__, request.metadata["attempt_key"] || "stream"}
    attempt = Process.get(key, 0) + 1
    Process.put(key, attempt)

    if attempt < 2 do
      {:error,
       %Error{
         type: :transport,
         provider: request.provider,
         message: "temporary network failure",
         retryable: true
       }}
    else
      [
        %StreamEvent{type: :stream_start},
        %StreamEvent{type: :text_delta, text: "stream retried"},
        %StreamEvent{type: :stream_end, usage: %Usage{total_tokens: 1}}
      ]
    end
  end
end
