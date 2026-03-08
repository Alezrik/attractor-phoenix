# Unified LLM Spec Compliance (AttractorEx)

This file tracks compliance of `AttractorEx.LLM.*` with the upstream unified LLM client specification.

## Source Documents

- Unified LLM spec: https://github.com/strongdm/attractor/blob/main/unified-llm-spec.md
- Coding-agent loop spec (consumer of this layer): https://github.com/strongdm/attractor/blob/main/coding-agent-loop-spec.md
- Upstream HEAD reviewed: `2f892efd63ee7c11f038856b90aae57c067b77c2` (checked 2026-03-06)

## Scope

Implementation:

1. `lib/attractor_ex/llm/client.ex`
2. `lib/attractor_ex/llm/request.ex`
3. `lib/attractor_ex/llm/response.ex`
4. `lib/attractor_ex/llm/message.ex`
5. `lib/attractor_ex/llm/usage.ex`
6. `lib/attractor_ex/llm/stream_event.ex`
7. `lib/attractor_ex/llm/provider_adapter.ex`

Tests and fixtures:

1. `test/attractor_ex/llm_client_test.exs`
2. `test/support/attractor_ex_test_llm_adapter.ex`
3. `test/support/attractor_ex_test_llm_error_adapter.ex`
4. `test/support/attractor_ex_test_unified_llm_adapter.ex`

## Section-by-Section Status

Legend: `implemented`, `partial`, `not implemented`.

| Upstream section | Status | Notes |
|---|---|---|
| `2. Architecture` | `partial` | Programmatic client config, provider resolution, middleware chain, adapter boundary, env-based construction (`from_env/1`), and module-level default client helpers are implemented. Model catalog and prompt caching machinery are still open. |
| `3. Data Model` | `partial` | Core request/response/usage/stream event/message structs exist. Messages now support tagged `MessagePart` content blocks, but full provider-round-trip multimodal semantics are still incomplete. |
| `4. Generation and Streaming` | `partial` | Low-level `complete`/raw `stream` plus `complete_with_request` and `stream_with_request` are implemented. High-level `generate`, stream accumulation, `generate_object`, and `stream_object` helpers are now implemented. Incremental typed object streaming is still not implemented. |
| `5. Tool Calling` | `partial` | Request/response fields support tool call payload transfer. Automatic high-level multi-step tool loop at this SDK layer is not implemented here (handled in agent session layer). |
| `6. Error Handling and Retry` | `not implemented` | Typed error hierarchy, retry taxonomy, backoff/retry-after handling are not implemented in this layer. |
| `7. Provider Adapter Contract` | `partial` | Adapter behavior contract (`complete`, optional `stream`) and unsupported-stream handling exist. Full provider translation guidance and concrete provider implementations are not included. |
| `8. Definition of Done` | `partial` | Core routing/middleware coverage exists and now includes env/default-client construction, message-part projection, stream accumulation, and JSON object helpers. Provider-native adapters, full multimodal round-trip parity, retries, and caching parity remain open. |

## Verified Behaviors (with tests)

1. Provider routing by explicit/default provider.
2. Errors for missing/unregistered providers.
3. Middleware request transformation for complete and stream.
4. `complete_with_request/2` and `stream_with_request/2` return resolved requests.
5. Stream adapter dispatch and unsupported-stream error path.
6. Request field pass-through including reasoning/cache usage counters.
7. `from_env/1` runtime construction and module-level default client helpers.
8. Message-part content projection for richer request payloads.
9. Stream accumulation into a normalized final response.
10. JSON object decoding for non-streaming and streaming helper APIs.

## Known Gaps vs Spec

1. Full content-part round-trip semantics across concrete provider adapters remain incomplete even though the normalized message model now supports tagged parts.
2. Incremental typed object streaming is not implemented; `stream_object/2` currently accumulates the underlying event stream before decoding.
3. Built-in tool-loop orchestration at unified client layer.
4. Error taxonomy and automatic retries with jitter/retry-after.
5. Native provider adapters for OpenAI Responses, Anthropic Messages, Gemini APIs.
6. Prompt caching provider-specific behaviors.

## Verification Commands

```bash
mix test test/attractor_ex/llm_client_test.exs
mix precommit
```
