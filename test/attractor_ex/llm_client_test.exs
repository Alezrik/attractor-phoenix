defmodule AttractorEx.LLMClientTest do
  use ExUnit.Case, async: true

  alias AttractorEx.LLM.{Client, Message, Request, Response}

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
end
