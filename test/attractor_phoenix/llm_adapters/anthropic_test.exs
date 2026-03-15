defmodule AttractorPhoenix.LLMAdapters.AnthropicTest do
  use ExUnit.Case, async: false

  alias AttractorEx.LLM.{Message, MessagePart, Request, StreamEvent}
  alias AttractorPhoenix.LLMAdapters.Anthropic
  alias AttractorPhoenix.LLMSetup

  setup do
    previous_req = Application.get_env(:attractor_phoenix, :llm_provider_req)

    Application.put_env(:attractor_phoenix, :llm_provider_req, AnthropicTestReq)
    LLMSetup.reset()
    {:ok, _settings} = LLMSetup.save_api_keys(%{"anthropic" => "test-key"})

    start_supervised!(%{
      id: AnthropicTestReq,
      start: {Agent, :start_link, [fn -> [] end, [name: AnthropicTestReq]]}
    })

    on_exit(fn ->
      restore_env(:attractor_phoenix, :llm_provider_req, previous_req)
      LLMSetup.reset()
    end)

    :ok
  end

  test "applies ephemeral prompt cache blocks and parses tool use" do
    request = %Request{
      model: "claude-opus-4-1",
      messages: [
        %Message{role: :system, content: "Follow repo rules"},
        %Message{
          role: :user,
          content: [
            %MessagePart{type: :text, text: "Inspect "},
            %MessagePart{
              type: :tool_result,
              data: %{"tool_use_id" => "tool-1", "content" => "ok"}
            }
          ]
        }
      ],
      cache: %{"strategy" => "ephemeral"},
      tools: [%{"name" => "read_file"}],
      tool_choice: "required"
    }

    assert %AttractorEx.LLM.Response{tool_calls: [%{"name" => "read_file"}]} =
             Anthropic.complete(request)

    payload = Agent.get(AnthropicTestReq, fn [payload | _rest] -> payload end)
    assert List.last(payload.system)["cache_control"] == %{"type" => "ephemeral"}
    assert payload.tool_choice == %{"type" => "any"}
  end

  test "streams text deltas and tool call starts from SSE payloads" do
    assert [
             %StreamEvent{type: :text_delta, text: "hi"},
             %StreamEvent{type: :tool_call, tool_call: %{"name" => "read_file"}},
             %StreamEvent{type: :stream_end},
             %StreamEvent{type: :stream_end}
           ] =
             Anthropic.stream(%Request{
               model: "claude-opus-4-1",
               messages: [%Message{role: :user, content: "hello"}]
             })
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end

defmodule AnthropicTestReq do
  def post(_url, opts) do
    Agent.update(__MODULE__, fn payloads -> [Keyword.fetch!(opts, :json) | payloads] end)

    if Keyword.has_key?(opts, :into) do
      into = Keyword.fetch!(opts, :into)

      {:cont, {_request, _response}} =
        into.(
          {:data,
           """
           data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"hi"}}
           data: {"type":"content_block_start","content_block":{"type":"tool_use","id":"tool-1","name":"read_file","input":{"path":"README.md"}}}
           data: {"type":"message_delta","usage":{"input_tokens":1,"output_tokens":1},"delta":{"stop_reason":"end_turn"}}
           data: {"type":"message_stop"}
           """},
          {%Req.Request{}, %Req.Response{status: 200, headers: %{}}}
        )

      {:ok, %Req.Response{status: 200, body: "", headers: %{}}}
    else
      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "id" => "msg_1",
           "content" => [
             %{
               "type" => "tool_use",
               "id" => "tool-1",
               "name" => "read_file",
               "input" => %{"path" => "README.md"}
             },
             %{"type" => "text", "text" => "done"}
           ],
           "usage" => %{
             "input_tokens" => 1,
             "output_tokens" => 2,
             "cache_creation_input_tokens" => 3
           },
           "stop_reason" => "tool_use"
         }
       }}
    end
  end
end
