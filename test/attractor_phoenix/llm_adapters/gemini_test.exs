defmodule AttractorPhoenix.LLMAdapters.GeminiTest do
  use ExUnit.Case, async: false

  alias AttractorEx.LLM.{Message, MessagePart, Request, StreamEvent}
  alias AttractorPhoenix.LLMAdapters.Gemini
  alias AttractorPhoenix.LLMSetup

  setup do
    previous_req = Application.get_env(:attractor_phoenix, :llm_provider_req)

    Application.put_env(:attractor_phoenix, :llm_provider_req, GeminiTestReq)
    LLMSetup.reset()
    {:ok, _settings} = LLMSetup.save_api_keys(%{"gemini" => "test-key"})

    start_supervised!(%{
      id: GeminiTestReq,
      start: {Agent, :start_link, [fn -> [] end, [name: GeminiTestReq]]}
    })

    on_exit(fn ->
      restore_env(:attractor_phoenix, :llm_provider_req, previous_req)
      LLMSetup.reset()
    end)

    :ok
  end

  test "maps multimodal parts and cached-content hooks" do
    assert %AttractorEx.LLM.Response{tool_calls: [%{"name" => "list_dir"}]} =
             Gemini.complete(%Request{
               model: "gemini-2.5-pro",
               messages: [
                 %Message{role: :system, content: "Be careful"},
                 %Message{
                   role: :user,
                   content: [
                     %MessagePart{type: :text, text: "Inspect"},
                     %MessagePart{type: :image, data: %{"url" => "https://example.test/cat.png"}}
                   ]
                 }
               ],
               cache: %{"key" => "cached-content-1"},
               tools: [%{"name" => "list_dir"}],
               tool_choice: "required",
               response_format: :json
             })

    payload = Agent.get(GeminiTestReq, fn [payload | _rest] -> payload end)
    assert payload.cachedContent == "cached-content-1"
    assert payload.toolConfig == %{functionCallingConfig: %{mode: "ANY"}}
    assert payload.generationConfig.responseMimeType == "application/json"
  end

  test "streams SSE candidate chunks into normalized events" do
    assert [
             %StreamEvent{type: :text_delta, text: "hello"},
             %StreamEvent{type: :tool_call, tool_call: %{"name" => "list_dir"}},
             %StreamEvent{type: :response, response: %AttractorEx.LLM.Response{text: "hello"}},
             %StreamEvent{type: :stream_end}
           ] =
             Gemini.stream(%Request{
               model: "gemini-2.5-pro",
               messages: [%Message{role: :user, content: "hello"}]
             })
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end

defmodule GeminiTestReq do
  def post(_url, opts) do
    Agent.update(__MODULE__, fn payloads -> [Keyword.fetch!(opts, :json) | payloads] end)

    if Keyword.has_key?(opts, :into) do
      into = Keyword.fetch!(opts, :into)

      {:cont, {_request, _response}} =
        into.(
          {:data,
           """
           data: {"candidates":[{"content":{"parts":[{"text":"hello"},{"functionCall":{"name":"list_dir","args":{"path":"."}}}]}}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":1,"totalTokenCount":2}}
           """},
          {%Req.Request{}, %Req.Response{status: 200, headers: %{}}}
        )

      {:ok, %Req.Response{status: 200, body: "", headers: %{}}}
    else
      {:ok,
       %Req.Response{
         status: 200,
         body: %{
           "candidates" => [
             %{
               "finishReason" => "STOP",
               "content" => %{
                 "parts" => [
                   %{"functionCall" => %{"name" => "list_dir", "args" => %{"path" => "."}}},
                   %{"text" => "hello"}
                 ]
               }
             }
           ],
           "usageMetadata" => %{
             "promptTokenCount" => 1,
             "candidatesTokenCount" => 1,
             "totalTokenCount" => 2
           }
         }
       }}
    end
  end
end
