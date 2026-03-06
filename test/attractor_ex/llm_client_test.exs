defmodule AttractorEx.LLMClientTest do
  use ExUnit.Case, async: true

  alias AttractorEx.LLM.{Client, Message, Request, Response, StreamEvent, Usage}

  test "routes request by explicit provider" do
    client = %Client{
      providers: %{
        "openai" => AttractorExTest.LLMAdapter,
        "anthropic" => AttractorExTest.LLMAdapter
      },
      default_provider: "anthropic"
    }

    request = %Request{
      provider: "openai",
      model: "gpt-5.2",
      messages: [%Message{role: :user, content: "hi"}]
    }

    assert %Response{text: text} = Client.complete(client, request)
    assert text =~ "provider=openai"
  end

  test "uses default provider when request provider is omitted" do
    client = %Client{
      providers: %{"anthropic" => AttractorExTest.LLMAdapter},
      default_provider: "anthropic"
    }

    request = %Request{
      model: "claude-opus-4-6",
      messages: [%Message{role: :user, content: "hello"}]
    }

    assert %Response{text: text} = Client.complete(client, request)
    assert text =~ "provider=anthropic"
  end

  test "returns error when provider is missing" do
    client = %Client{providers: %{"openai" => AttractorExTest.LLMAdapter}}
    request = %Request{model: "gpt-5.2", messages: []}
    assert {:error, :provider_not_configured} = Client.complete(client, request)
  end

  test "returns error when provider is not registered" do
    client = %Client{
      providers: %{"openai" => AttractorExTest.LLMAdapter},
      default_provider: "gemini"
    }

    request = %Request{model: "gemini-3-flash-preview", messages: []}
    assert {:error, {:provider_not_registered, "gemini"}} = Client.complete(client, request)
  end

  test "middleware can transform request before adapter call" do
    middleware = fn request, next ->
      next.(%{request | model: "gpt-5.2-codex"})
    end

    client = %Client{
      providers: %{"openai" => AttractorExTest.LLMAdapter},
      default_provider: "openai",
      middleware: [middleware]
    }

    request = %Request{model: "gpt-5.2", messages: [%Message{role: :user, content: "hi"}]}
    assert %Response{text: text} = Client.complete(client, request)
    assert text =~ "model=gpt-5.2-codex"
  end

  test "middleware can set provider before routing when request/provider default are blank" do
    middleware = fn request, next ->
      next.(%{request | provider: "openai"})
    end

    client = %Client{
      providers: %{"openai" => AttractorExTest.LLMAdapter},
      middleware: [middleware]
    }

    request = %Request{model: "gpt-5.2", messages: [%Message{role: :user, content: "hi"}]}
    assert %Response{text: text} = Client.complete(client, request)
    assert text =~ "provider=openai"
  end

  test "middleware can reroute provider even when request has provider set" do
    middleware = fn request, next ->
      next.(%{request | provider: "anthropic"})
    end

    client = %Client{
      providers: %{
        "openai" => AttractorExTest.LLMAdapter,
        "anthropic" => AttractorExTest.LLMAdapter
      },
      default_provider: "openai",
      middleware: [middleware]
    }

    request = %Request{
      provider: "openai",
      model: "claude-opus-4-6",
      messages: [%Message{role: :user, content: "hi"}]
    }

    assert %Response{text: text} = Client.complete(client, request)
    assert text =~ "provider=anthropic"
  end

  test "stream routes to adapter and returns stream events" do
    client = %Client{
      providers: %{"openai" => AttractorExTest.LLMAdapter},
      default_provider: "openai"
    }

    events =
      client
      |> Client.stream(%Request{
        model: "gpt-5.2",
        messages: [%Message{role: :user, content: "hi"}]
      })
      |> Enum.to_list()

    assert [
             %StreamEvent{type: :stream_start},
             %StreamEvent{type: :text_delta, text: "provider=openai"}
           ] =
             events
  end

  test "stream returns unsupported error when provider has no stream callback" do
    client = %Client{
      providers: %{"openai" => AttractorExTest.LLMErrorAdapter},
      default_provider: "openai"
    }

    assert {:error, {:stream_not_supported, "openai"}} =
             Client.stream(client, %Request{model: "gpt-5.2", messages: []})
  end

  test "streaming middleware can transform request before adapter call" do
    middleware = fn request, next -> next.(%{request | provider: "anthropic"}) end

    client = %Client{
      providers: %{
        "openai" => AttractorExTest.LLMAdapter,
        "anthropic" => AttractorExTest.LLMAdapter
      },
      default_provider: "openai",
      streaming_middleware: [middleware]
    }

    events = Client.stream(client, %Request{model: "gpt-5.2", messages: []}) |> Enum.to_list()

    assert Enum.any?(events, fn
             %StreamEvent{type: :text_delta, text: "provider=anthropic"} -> true
             _ -> false
           end)
  end

  describe "unified LLM spec coverage" do
    test "request fields are preserved and usage includes reasoning/cache counters" do
      client = %Client{
        providers: %{"openai" => AttractorExTest.UnifiedLLMAdapter},
        default_provider: "openai"
      }

      request = %Request{
        model: "gpt-5.2",
        messages: [%Message{role: :user, content: "hi"}],
        max_tokens: 256,
        temperature: 0.3,
        top_p: 0.9,
        stop_sequences: ["END", "DONE"],
        reasoning_effort: "medium",
        response_format: %{type: :json_schema, schema: %{"type" => "object"}},
        provider_options: %{"region" => "us"},
        metadata: %{"trace_id" => "abc-123"}
      }

      assert %Response{usage: %Usage{} = usage, raw: %{"request_snapshot" => snapshot}} =
               Client.complete(client, request)

      assert snapshot["model"] == "gpt-5.2"
      assert snapshot["provider"] == "openai"
      assert snapshot["max_tokens"] == 256
      assert snapshot["temperature"] == 0.3
      assert snapshot["top_p"] == 0.9
      assert snapshot["stop_sequences"] == ["END", "DONE"]
      assert snapshot["reasoning_effort"] == "medium"
      assert snapshot["response_format"] == %{type: :json_schema, schema: %{"type" => "object"}}
      assert snapshot["provider_options"] == %{"region" => "us"}
      assert snapshot["metadata"] == %{"trace_id" => "abc-123"}

      assert usage.reasoning_tokens == 20
      assert usage.cache_read_tokens == 7
      assert usage.cache_write_tokens == 3
    end

    test "complete_with_request returns resolved provider on default routing" do
      client = %Client{
        providers: %{"openai" => AttractorExTest.UnifiedLLMAdapter},
        default_provider: "openai"
      }

      request = %Request{model: "gpt-5.2", messages: [%Message{role: :user, content: "hi"}]}

      assert {:ok, %Response{}, %Request{} = resolved_request} =
               Client.complete_with_request(client, request)

      assert resolved_request.provider == "openai"
      assert resolved_request.model == "gpt-5.2"
    end

    test "stream_with_request returns stream events and resolved provider" do
      client = %Client{
        providers: %{"openai" => AttractorExTest.UnifiedLLMAdapter},
        default_provider: "openai"
      }

      request = %Request{model: "gpt-5.2", messages: [%Message{role: :user, content: "hi"}]}

      assert {:ok, events, %Request{} = resolved_request} =
               Client.stream_with_request(client, request)

      assert resolved_request.provider == "openai"

      assert [
               %StreamEvent{type: :stream_start},
               %StreamEvent{type: :text_delta, text: "chunk"},
               %StreamEvent{type: :reasoning_delta, reasoning: "thinking"},
               %StreamEvent{
                 type: :tool_call,
                 tool_call: %{"id" => "call-1", "name" => "echo"}
               },
               %StreamEvent{
                 type: :tool_result,
                 tool_result: %{"id" => "call-1", "output" => "done"}
               },
               %StreamEvent{
                 type: :response,
                 response: %Response{text: "final", finish_reason: "stop"}
               },
               %StreamEvent{
                 type: :stream_end,
                 usage: %Usage{total_tokens: 1}
               },
               %StreamEvent{
                 type: :error,
                 error: {:simulated_error, "openai"},
                 raw: %{"request_snapshot" => %{"provider" => "openai"}}
               }
             ] = Enum.to_list(events)
    end
  end
end
