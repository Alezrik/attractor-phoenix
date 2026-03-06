# Unified LLM Spec Compliance (AttractorEx)

This document tracks how `AttractorEx` aligns with the unified LLM client specification.

## Upstream Reference

- Spec URL: https://github.com/strongdm/attractor/blob/main/unified-llm-spec.md
- Baseline commit currently targeted by this repository: `main` (tracked by spec URL)

## Implemented Areas

Implementation modules:

1. `lib/attractor_ex/llm/request.ex`
2. `lib/attractor_ex/llm/response.ex`
3. `lib/attractor_ex/llm/usage.ex`
4. `lib/attractor_ex/llm/stream_event.ex`
5. `lib/attractor_ex/llm/provider_adapter.ex`
6. `lib/attractor_ex/llm/client.ex`

Primary verification tests:

1. `test/attractor_ex/llm_client_test.exs`

## Compliance Matrix

### Core client routing and middleware

Covered behavior:

1. Provider routing using explicit request provider or default provider.
2. Error returns for unconfigured provider or unregistered provider.
3. Request middleware wrapping blocking calls.
4. Streaming middleware wrapping streaming calls.

### Unified request and response model

Covered behavior:

1. Request fields for model/provider/messages/max_tokens/temperature/reasoning_effort.
2. Additional request fields aligned with spec: `top_p`, `stop_sequences`, and `response_format`.
3. Response usage shape includes reasoning and cache token counters.

### Provider adapter contract

Covered behavior:

1. Required `complete/1` callback.
2. Optional `stream/1` callback.
3. Stream capability detection in client with explicit `{:stream_not_supported, provider}` error.

### Streaming model

Covered behavior:

1. Low-level `Client.stream/2` API with provider routing and middleware.
2. Unified stream event type via `AttractorEx.LLM.StreamEvent`.
3. Basic stream event categories: lifecycle, text deltas, reasoning deltas, tool events, final response, and error.

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

## Maintenance Notes

1. Update this document when upstream unified spec changes.
2. Prefer adding tests before expanding request/response semantics.
3. Keep README references synchronized with this document.
