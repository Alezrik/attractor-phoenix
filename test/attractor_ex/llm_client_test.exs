defmodule AttractorEx.LLMClientTest do
  use ExUnit.Case, async: true

  alias AttractorEx.LLM.{Client, Message, MessagePart, Request, Response, StreamEvent, Usage}

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

  test "middleware can short-circuit complete with a direct response" do
    middleware = fn _request, _next ->
      %Response{text: "short-circuited", usage: %Usage{}, finish_reason: "stop"}
    end

    client = %Client{
      providers: %{"openai" => AttractorExTest.LLMAdapter},
      default_provider: "openai",
      middleware: [middleware]
    }

    assert %Response{text: "short-circuited"} =
             Client.complete(client, %Request{model: "gpt-5.2", messages: []})
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

  describe "default client and runtime construction" do
    test "arity-1 helpers return an error when no default client is configured" do
      Client.clear_default()

      assert is_nil(Client.default())

      assert {:error, :default_client_not_configured} =
               Client.complete(%Request{model: "gpt-5.2", messages: []})

      assert {:error, :default_client_not_configured} =
               Client.stream(%Request{model: "gpt-5.2", messages: []})

      assert {:error, :default_client_not_configured} =
               Client.generate_object(%Request{model: "gpt-5.2", messages: []})
    end

    test "new normalizes blank provider names and ignores invalid adapters" do
      client =
        Client.new(
          providers: %{" openai " => AttractorExTest.LLMAdapter, "" => "ignored"},
          default_provider: "  "
        )

      assert client.providers == %{"openai" => AttractorExTest.LLMAdapter}
      assert is_nil(client.default_provider)
    end

    test "from_env builds a client from application config" do
      Application.put_env(:attractor_phoenix, :attractor_ex_llm,
        providers: %{"openai" => AttractorExTest.LLMAdapter},
        default_provider: "openai"
      )

      on_exit(fn -> Application.delete_env(:attractor_phoenix, :attractor_ex_llm) end)

      client = Client.from_env()

      assert %Client{default_provider: "openai"} = client
      assert client.providers["openai"] == AttractorExTest.LLMAdapter
    end

    test "from_env supports map config and env var override for default provider" do
      Application.put_env(:attractor_phoenix, :attractor_ex_llm, %{
        "providers" => %{"openai" => AttractorExTest.LLMAdapter},
        "default_provider" => "anthropic"
      })

      System.put_env("ATTRACTOR_EX_LLM_DEFAULT_PROVIDER", "openai")

      on_exit(fn ->
        Application.delete_env(:attractor_phoenix, :attractor_ex_llm)
        System.delete_env("ATTRACTOR_EX_LLM_DEFAULT_PROVIDER")
      end)

      client = Client.from_env()

      assert client.default_provider == "openai"
      assert client.providers["openai"] == AttractorExTest.LLMAdapter
    end

    test "from_env opts override configured middleware values" do
      configured = fn request, next -> next.(%{request | provider: "anthropic"}) end
      override = fn request, next -> next.(%{request | provider: "openai"}) end

      Application.put_env(:attractor_phoenix, :attractor_ex_llm,
        providers: %{
          "openai" => AttractorExTest.LLMAdapter,
          "anthropic" => AttractorExTest.LLMAdapter
        },
        default_provider: "anthropic",
        middleware: [configured]
      )

      on_exit(fn -> Application.delete_env(:attractor_phoenix, :attractor_ex_llm) end)

      client = Client.from_env(middleware: [override])

      assert %Response{text: text} =
               Client.complete(client, %Request{model: "gpt-5.2", messages: []})

      assert text =~ "provider=openai"
    end

    test "arity-1 helpers use the configured default client" do
      _client =
        %Client{
          providers: %{"openai" => AttractorExTest.LLMAdapter},
          default_provider: "openai"
        }
        |> Client.put_default()

      on_exit(fn -> Client.clear_default() end)

      assert %Response{text: text} =
               Client.generate(%Request{
                 model: "gpt-5.2",
                 messages: [%Message{role: :user, content: "hi"}]
               })

      assert text =~ "provider=openai"

      assert %Response{text: "provider=openai"} =
               Client.accumulate_stream(%Request{model: "gpt-5.2", messages: []})
    end
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

      assert snapshot["messages"] == [
               %{"role" => :user, "content" => "hi", "tool_call_id" => nil, "name" => nil}
             ]

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

    test "generate_with_request is an alias for the high-level API" do
      client = %Client{
        providers: %{"openai" => AttractorExTest.UnifiedLLMAdapter},
        default_provider: "openai"
      }

      request = %Request{model: "gpt-5.2", messages: [%Message{role: :user, content: "hi"}]}

      assert {:ok, %Response{text: "ok"}, %Request{provider: "openai"}} =
               Client.generate_with_request(client, request)
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

    test "message content parts preserve a text projection for adapters" do
      client = %Client{
        providers: %{"openai" => AttractorExTest.UnifiedLLMAdapter},
        default_provider: "openai"
      }

      request = %Request{
        model: "gpt-5.2",
        messages: [
          %Message{
            role: :user,
            content: [
              %MessagePart{type: :text, text: "Describe this asset "},
              %MessagePart{type: :image, data: %{"url" => "https://example.test/cat.png"}},
              %MessagePart{type: :thinking, text: "carefully"}
            ]
          }
        ]
      }

      assert %Response{raw: %{"request_snapshot" => snapshot}} = Client.complete(client, request)

      assert snapshot["messages"] == [
               %{
                 "role" => :user,
                 "content" => "Describe this asset [image]carefully",
                 "tool_call_id" => nil,
                 "name" => nil
               }
             ]
    end

    test "message text projection handles map parts and unknown payloads" do
      assert Message.content_text([
               %{"type" => "tool_result", "text" => "done"},
               %{"type" => "json"},
               :ignored
             ]) == "[tool result: done][json]"

      assert Message.content_text(nil) == ""
    end

    test "message part projection handles struct and map variants" do
      assert MessagePart.text_projection(%MessagePart{type: :audio, text: "clip"}) ==
               "[audio: clip]"

      assert MessagePart.text_projection(%{"type" => "thinking", "text" => "reason"}) ==
               "reason"

      assert MessagePart.text_projection(%{"type" => "unknown"}) == "[text]"
    end

    test "accumulate_stream returns a normalized response from stream events" do
      client = %Client{
        providers: %{"openai" => AttractorExTest.UnifiedLLMAdapter},
        default_provider: "openai"
      }

      assert %Response{} =
               response =
               Client.accumulate_stream(client, %Request{
                 model: "gpt-5.2",
                 messages: [%Message{role: :user, content: "hi"}]
               })

      assert response.text == "final"
      assert response.reasoning == "thinking"
      assert response.tool_calls == [%{"id" => "call-1", "name" => "echo"}]
      assert response.usage.total_tokens == 1
      assert response.raw["stream_errors"] == [{:simulated_error, "openai"}]
    end

    test "accumulate_stream falls back to usage totals from input/output counters" do
      base_client = %Client{
        providers: %{"openai" => AttractorExTest.LLMAdapter},
        default_provider: "openai"
      }

      middleware = fn request, _next ->
        {:ok,
         [
           %StreamEvent{type: :stream_start},
           %StreamEvent{
             type: :response,
             response: %Response{text: "done", usage: %Usage{input_tokens: 2, output_tokens: 3}}
           }
         ], %{request | provider: "openai"}}
      end

      client = %{base_client | streaming_middleware: [middleware]}

      assert %Response{usage: %Usage{total_tokens: 5}} =
               Client.accumulate_stream(client, %Request{model: "gpt-5.2", messages: []})
    end

    test "generate_object decodes JSON responses" do
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

    test "generate_object returns a decoding error for non-json output" do
      client = %Client{
        providers: %{"openai" => AttractorExTest.UnifiedLLMAdapter},
        default_provider: "openai"
      }

      assert {:error, {:invalid_json_response, _message}} =
               Client.generate_object(client, %Request{
                 model: "gpt-5.2",
                 messages: [%Message{role: :user, content: "hi"}]
               })
    end

    test "stream_object rejects scalar JSON values" do
      client = %Client{
        providers: %{"openai" => AttractorExTest.LLMAdapter},
        default_provider: "openai",
        streaming_middleware: [
          fn request, _next ->
            {:ok,
             [
               %StreamEvent{
                 type: :response,
                 response: %Response{text: "123", usage: %Usage{}, finish_reason: "stop"}
               }
             ], %{request | provider: "openai"}}
          end
        ]
      }

      assert {:error, :json_response_must_be_object_or_array} =
               Client.stream_object(client, %Request{model: "gpt-5.2", messages: []})
    end

    test "stream_object decodes JSON after accumulating stream output" do
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
end
