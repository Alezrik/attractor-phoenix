defmodule AttractorEx.LLMErrorTest do
  use ExUnit.Case, async: true

  alias AttractorEx.LLM.{Error, RetryPolicy}

  test "normalizes HTTP status classes into typed provider errors" do
    assert %Error{type: :authentication, retryable: false, code: "bad_auth"} =
             Error.from_http_response("openai", 401, %{
               "error" => %{"message" => "bad key", "code" => "bad_auth"}
             })

    assert %Error{type: :rate_limited, retryable: true, retry_after_ms: 3_000} =
             Error.from_http_response(
               "anthropic",
               429,
               %{"error" => %{"message" => "slow down"}},
               %{"retry-after" => ["3"]}
             )

    assert %Error{type: :server, retryable: true} =
             Error.from_http_response("gemini", 503, %{"message" => "unavailable"})
  end

  test "normalizes invalid request and generic api statuses" do
    assert %Error{type: :invalid_request, details: %{"field" => "model"}} =
             Error.from_http_response("openai", 422, %{
               "message" => "bad request",
               "field" => "model"
             })

    assert %Error{type: :api, message: "HTTP 409"} =
             Error.from_http_response("openai", 409, %{})
  end

  test "normalizes transport and timeout reasons" do
    assert %Error{type: :transport, retryable: true} =
             Error.transport("openai", :closed)

    assert %Error{type: :timeout, retryable: true} =
             Error.transport("openai", {:timeout, :read})

    assert %Error{type: :timeout, retryable: true} =
             Error.normalize({:timeout, "socket timed out"}, provider: "openai")
  end

  test "normalizes bare strings tuples and unknown terms" do
    assert %Error{type: :api, message: "boom"} = Error.normalize("boom", provider: "openai")

    assert %Error{type: :unsupported} =
             Error.normalize({:unsupported, "no stream"}, provider: "openai")

    assert %Error{type: :unknown, raw: :mystery} = Error.normalize(:mystery, provider: "openai")
  end

  test "retry policy normalization and retry decisions" do
    policy =
      RetryPolicy.new(max_attempts: 3, base_delay_ms: 10, max_delay_ms: 20, jitter_ratio: 0.0)

    error = %Error{type: :rate_limited, retryable: true}

    assert policy.max_attempts == 3
    assert RetryPolicy.enabled?(policy)
    assert RetryPolicy.retry?(policy, error, 1)
    refute RetryPolicy.retry?(policy, error, 3)
    assert RetryPolicy.delay_ms(policy, error, 2) == 20
  end

  test "retry policy honors retry_after and custom retry predicate" do
    policy =
      RetryPolicy.new(%{
        max_attempts: 2,
        base_delay_ms: 0,
        max_delay_ms: 10,
        jitter_ratio: 0.0,
        retry_if: fn error, attempt -> error.type == :api and attempt == 1 end
      })

    error = %Error{type: :api, retryable: false, retry_after_ms: 7}

    assert RetryPolicy.retry?(policy, error, 1)
    refute RetryPolicy.retry?(policy, error, 2)
    assert RetryPolicy.delay_ms(policy, error, 1) == 7
  end

  test "retry policy handles nil and malformed input" do
    assert RetryPolicy.new(nil) == nil
    assert %RetryPolicy{max_attempts: 1} = RetryPolicy.new(%{"max_attempts" => -1})
    refute RetryPolicy.enabled?(RetryPolicy.new(%{}))
  end
end
