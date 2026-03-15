defmodule AttractorPhoenix.LLMAdapters.OpenAITest do
  use ExUnit.Case, async: false

  alias AttractorEx.LLM.{Message, MessagePart, Request, StreamEvent}
  alias AttractorPhoenix.LLMAdapters.OpenAI
  alias AttractorPhoenix.LLMSetup

  setup do
    previous_req = Application.get_env(:attractor_phoenix, :llm_provider_req)

    Application.put_env(:attractor_phoenix, :llm_provider_req, OpenAITestReq)
    LLMSetup.reset()
    {:ok, _settings} = LLMSetup.save_api_keys(%{"openai" => "test-key"})

    start_supervised!(%{
      id: OpenAITestReq,
      start: {Agent, :start_link, [fn -> [] end, [name: OpenAITestReq]]}
    })

    on_exit(fn ->
      restore_env(:attractor_phoenix, :llm_provider_req, previous_req)
      LLMSetup.reset()
    end)

    :ok
  end

  test "omits temperature for codex-style models and translates tools/cache hooks" do
    request = %Request{
      model: "codex-5.3",
      messages: [
        %Message{role: :system, content: "You are helpful"},
        %Message{
          role: :user,
          content: [
            %MessagePart{type: :text, text: "Inspect "},
            %MessagePart{type: :image, data: %{"url" => "https://example.test/cat.png"}}
          ]
        },
        %Message{role: :tool, tool_call_id: "call-1", content: "done"}
      ],
      tools: [%{"name" => "read_file", "description" => "Read a file"}],
      tool_choice: "auto",
      cache: %{"key" => "prompt-1", "ttl_seconds" => 60},
      temperature: 0.2,
      reasoning_effort: "medium",
      response_format: :json
    }

    assert %AttractorEx.LLM.Response{text: "ok", tool_calls: [%{"name" => "shell"}]} =
             OpenAI.complete(request)

    payload = last_payload()
    refute Map.has_key?(payload, :temperature)
    assert payload.model == "codex-5.3"
    assert payload.instructions == "You are helpful"
    assert payload.prompt_cache_key == "prompt-1"
    assert payload.prompt_cache_ttl_seconds == 60
    assert payload.text == %{format: %{type: "json_object"}}

    assert payload.tools == [
             %{
               "type" => "function",
               "name" => "read_file",
               "description" => "Read a file",
               "parameters" => %{"type" => "object", "properties" => %{}}
             }
           ]

    assert Enum.any?(payload.input, fn item ->
             item[:type] == "message" and
               Enum.any?(item[:content], &(&1[:type] == "input_image"))
           end)

    assert Enum.any?(payload.input, &(&1[:type] == "function_call_output"))
  end

  test "streams normalized text and tool-call events from SSE payloads" do
    assert [
             %StreamEvent{type: :text_delta, text: "hel"},
             %StreamEvent{type: :tool_call, tool_call: %{"name" => "shell"}},
             %StreamEvent{type: :response, response: %AttractorEx.LLM.Response{text: "hello"}},
             %StreamEvent{type: :stream_end}
           ] =
             OpenAI.stream(%Request{
               model: "gpt-4.1-mini",
               messages: [%Message{role: :user, content: "hi"}]
             })
  end

  defp last_payload do
    Agent.get(OpenAITestReq, fn [payload | _rest] -> payload end)
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end

defmodule OpenAITestReq do
  def post(_url, opts) do
    Agent.update(__MODULE__, fn payloads -> [Keyword.fetch!(opts, :json) | payloads] end)

    if Keyword.has_key?(opts, :into) do
      into = Keyword.fetch!(opts, :into)
      response = %Req.Response{status: 200, headers: %{}}
      request = %Req.Request{}

      {:cont, {_request, _response}} =
        into.(
          {:data,
           """
           data: {"type":"response.output_text.delta","delta":"hel"}
           data: {"type":"response.output_item.added","item":{"type":"function_call","call_id":"call-1","name":"shell","arguments":"{\\"command\\":\\"pwd\\"}"}}
           data: {"type":"response.completed","response":{"id":"resp_stream","status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"hello"}]}],"usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}}
           data: [DONE]
           """},
          {request, response}
        )

      {:ok, %Req.Response{status: 200, body: "", headers: %{}}}
    else
      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "id" => "resp_test",
           "status" => "completed",
           "output" => [
             %{
               "type" => "function_call",
               "call_id" => "call-1",
               "name" => "shell",
               "arguments" => "{\"command\":\"pwd\"}"
             },
             %{
               "type" => "message",
               "content" => [%{"type" => "output_text", "text" => "ok"}]
             }
           ],
           "usage" => %{
             "input_tokens" => 1,
             "output_tokens" => 1,
             "total_tokens" => 2,
             "input_tokens_details" => %{"cached_tokens" => 5}
           }
         }
       }}
    end
  end
end
