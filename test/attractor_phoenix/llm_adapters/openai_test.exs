defmodule AttractorPhoenix.LLMAdapters.OpenAITest do
  use ExUnit.Case, async: false

  alias AttractorEx.LLM.{Message, Request}
  alias AttractorPhoenix.LLMAdapters.OpenAI
  alias AttractorPhoenix.LLMSetup

  setup do
    previous_req = Application.get_env(:attractor_phoenix, :llm_provider_req)

    Application.put_env(:attractor_phoenix, :llm_provider_req, OpenAITestReq)
    LLMSetup.reset()
    {:ok, _settings} = LLMSetup.save_api_keys(%{"openai" => "test-key"})

    on_exit(fn ->
      restore_env(:attractor_phoenix, :llm_provider_req, previous_req)
      LLMSetup.reset()
    end)

    start_supervised!(%{
      id: OpenAITestReq,
      start: {Agent, :start_link, [fn -> nil end, [name: OpenAITestReq]]}
    })

    :ok
  end

  test "omits temperature for codex-style models" do
    request = %Request{
      model: "codex-5.3",
      messages: [%Message{role: :user, content: "hi"}],
      temperature: 0.2,
      reasoning_effort: "medium"
    }

    assert %AttractorEx.LLM.Response{text: "ok"} = OpenAI.complete(request)

    payload = Agent.get(OpenAITestReq, & &1)
    refute Map.has_key?(payload, :temperature)
    assert payload.model == "codex-5.3"
  end

  test "keeps temperature for standard chat models" do
    request = %Request{
      model: "gpt-4.1-mini",
      messages: [%Message{role: :user, content: "hi"}],
      temperature: 0.2
    }

    assert %AttractorEx.LLM.Response{text: "ok"} = OpenAI.complete(request)

    payload = Agent.get(OpenAITestReq, & &1)
    assert payload.temperature == 0.2
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end

defmodule OpenAITestReq do
  def post(_url, opts) do
    Agent.update(__MODULE__, fn _ -> Keyword.fetch!(opts, :json) end)

    {:ok,
     %Req.Response{
       status: 200,
       body: %{
         "id" => "resp_test",
         "status" => "completed",
         "output" => [
           %{
             "type" => "message",
             "content" => [%{"type" => "output_text", "text" => "ok"}]
           }
         ],
         "usage" => %{"input_tokens" => 1, "output_tokens" => 1, "total_tokens" => 2}
       }
     }}
  end
end
