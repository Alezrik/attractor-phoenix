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
| `2. Architecture` | `partial` | Programmatic client config, provider resolution, middleware chain, adapter boundary are implemented. Env-based construction, model catalog, prompt caching machinery, and module-level default client are not complete. |
| `3. Data Model` | `partial` | Core request/response/usage/stream event/message structs exist. Full multimodal tagged unions and richer content part model are not fully implemented. |
| `4. Generation and Streaming` | `partial` | Low-level `complete` and `stream` implemented; `complete_with_request` and `stream_with_request` included. High-level `generate`, `stream` accumulator APIs, and object generation APIs are not implemented. |
| `5. Tool Calling` | `partial` | Request/response fields support tool call payload transfer. Automatic high-level multi-step tool loop at this SDK layer is not implemented here (handled in agent session layer). |
| `6. Error Handling and Retry` | `not implemented` | Typed error hierarchy, retry taxonomy, backoff/retry-after handling are not implemented in this layer. |
| `7. Provider Adapter Contract` | `partial` | Adapter behavior contract (`complete`, optional `stream`) and unsupported-stream handling exist. Full provider translation guidance and concrete provider implementations are not included. |
| `8. Definition of Done` | `partial` | Core routing/middleware coverage exists; large parts (provider-native adapters, full message model, high-level APIs, retry/caching parity matrix) remain open. |

## Verified Behaviors (with tests)

1. Provider routing by explicit/default provider.
2. Errors for missing/unregistered providers.
3. Middleware request transformation for complete and stream.
4. `complete_with_request/2` and `stream_with_request/2` return resolved requests.
5. Stream adapter dispatch and unsupported-stream error path.
6. Request field pass-through including reasoning/cache usage counters.

## Known Gaps vs Spec

1. `Client.from_env()` and module-level default singleton client.
2. Full content-part model (image/audio/document/tool/thinking blocks) and round-trip semantics.
3. High-level APIs: `generate`, `stream` result accumulators, `generate_object`, `stream_object`.
4. Built-in tool-loop orchestration at unified client layer.
5. Error taxonomy and automatic retries with jitter/retry-after.
6. Native provider adapters for OpenAI Responses, Anthropic Messages, Gemini APIs.
7. Prompt caching provider-specific behaviors.

## Verification Commands

```bash
mix test test/attractor_ex/llm_client_test.exs
mix precommit
```
