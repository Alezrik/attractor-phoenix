# Unified LLM Spec Compliance (AttractorEx)

This document records how `AttractorEx.LLM` modules map to the upstream strongDM unified LLM behavior and where that behavior is validated by tests.

## Scope

Implementation scope:

1. `lib/attractor_ex/llm/request.ex`
2. `lib/attractor_ex/llm/response.ex`
3. `lib/attractor_ex/llm/usage.ex`
4. `lib/attractor_ex/llm/stream_event.ex`
5. `lib/attractor_ex/llm/provider_adapter.ex`
6. `lib/attractor_ex/llm/client.ex`

Primary verification tests and fixtures:

1. `test/attractor_ex/llm_client_test.exs`
2. `test/support/attractor_ex_test_llm_adapter.ex`
3. `test/support/attractor_ex_test_llm_error_adapter.ex`
4. `test/support/attractor_ex_test_unified_llm_adapter.ex`

## Compliance Matrix

### Core client routing and middleware

1. Provider routing using explicit request provider or default provider.
2. Error returns for unconfigured provider or unregistered provider.
3. Request middleware wrapping blocking calls.
4. Streaming middleware wrapping streaming calls.
5. `complete_with_request/2` and `stream_with_request/2` return resolved request values.

Tests:

- `routes request by explicit provider`
- `uses default provider when request provider is omitted`
- `returns error when provider is missing`
- `returns error when provider is not registered`
- `middleware can transform request before adapter call`
- `middleware can set provider before routing when request/provider default are blank`
- `middleware can reroute provider even when request has provider set`
- `streaming middleware can transform request before adapter call`
- `complete_with_request returns resolved provider on default routing`
- `stream_with_request returns stream events and resolved provider`

### Unified request and response model

1. Request fields for model/provider/messages/max_tokens/temperature/reasoning_effort.
2. Additional request fields aligned with spec: `top_p`, `stop_sequences`, and `response_format`.
3. Response usage shape includes reasoning and cache token counters.

Tests:

- `request fields are preserved and usage includes reasoning/cache counters`

### Provider adapter contract

1. Required `complete/1` callback.
2. Optional `stream/1` callback.
3. Stream capability detection in client with explicit `{:stream_not_supported, provider}` error.

Tests:

- `routes request by explicit provider`
- `stream routes to adapter and returns stream events`
- `stream returns unsupported error when provider has no stream callback`

### Streaming model

1. Low-level `Client.stream/2` API with provider routing and middleware.
2. Unified stream event type via `AttractorEx.LLM.StreamEvent`.
3. Basic stream event categories: lifecycle, text deltas, reasoning deltas, tool events, final response, and error.

Tests:

- `stream routes to adapter and returns stream events`
- `stream_with_request returns stream events and resolved provider`

## Not Yet Implemented

1. High-level convenience API (`generate`, `stream`, `generate_object`) and module-level default client.
2. Structured output parsing/validation loop (`json_schema`) execution helpers.
3. Built-in retry policies and typed SDK error hierarchy.
4. Concrete provider adapters for OpenAI Responses API, Anthropic Messages API, and Gemini native API.

## Verification Commands

```bash
mix test test/attractor_ex/llm_client_test.exs
mix precommit
```

## Upstream Spec Link

- https://github.com/strongdm/attractor/blob/main/unified-llm-spec.md

Keep this document in sync with any upstream unified-llm-spec changes and add/adjust tests first before implementation changes.
