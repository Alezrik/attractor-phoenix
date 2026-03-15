defmodule AttractorEx.Conformance.UnifiedLLMTest do
  use ExUnit.Case, async: true

  alias AttractorEx.LLM.{Client, Message, Request}

  test "generates a JSON object through the provider-agnostic client" do
    client = %Client{
      providers: %{"openai" => AttractorExTest.UnifiedLLMAdapter},
      default_provider: "openai"
    }

    assert {:ok, %{"provider" => "openai", "model" => "gpt-5.2"}} =
             Client.generate_object(client, %Request{
               model: "gpt-5.2",
               messages: [%Message{role: :user, content: "hi"}],
               metadata: %{"json_mode" => true}
             })
  end

  test "accumulates streaming output into a normalized JSON object" do
    client = %Client{
      providers: %{"openai" => AttractorExTest.UnifiedLLMAdapter},
      default_provider: "openai"
    }

    assert {:ok, %{"provider" => "openai", "streamed" => true}} =
             Client.stream_object(client, %Request{
               model: "gpt-5.2",
               messages: [%Message{role: :user, content: "hi"}],
               metadata: %{"json_mode" => true}
             })
  end
end
