# Unified LLM Spec Compliance (AttractorEx)

This file tracks compliance of `AttractorEx.LLM.*` with the upstream unified LLM client specification.

The durable HTTP runtime introduced for the runtime-foundation workstream is transport
and orchestration infrastructure. It does not change the unified LLM request and
response contract directly, but it does make persisted run, checkpoint, and event
replay state available around LLM-backed pipelines.

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
| `2. Architecture` | `implemented` | Programmatic client config, provider resolution, middleware chain, adapter boundary, env-based construction (`from_env/1`), module-level default client helpers, client/request retry policy wiring, and provider cache hooks are implemented. |
| `3. Data Model` | `partial` | Core request/response/usage/stream event/message structs exist, including typed error/retry metadata, cache hints, `MessagePart` multimodal blocks, and `:object_delta` stream events. Some provider-specific multimodal edge cases are still normalized conservatively. |
| `4. Generation and Streaming` | `implemented` | Low-level `complete`/raw `stream`, resolved-request helpers, stream accumulation, `generate_object`, `stream_object`, and incremental `stream_object_deltas` JSON streaming are implemented. Native OpenAI, Anthropic, and Gemini adapters now translate both non-streaming and streaming flows. |
| `5. Tool Calling` | `partial` | Request/response fields support tool call payload transfer. Automatic high-level multi-step tool loop at this SDK layer is not implemented here (handled in agent session layer). |
| `6. Error Handling and Retry` | `implemented` | `AttractorEx.LLM.Error` and `AttractorEx.LLM.RetryPolicy` provide typed provider/transport errors, retryability metadata, backoff, and `retry-after` handling at the client layer. |
| `7. Provider Adapter Contract` | `implemented` | Adapter behavior contract (`complete`, optional `stream`) is exercised by concrete OpenAI, Anthropic, and Gemini adapters with normalized text, tool-call, reasoning, usage, and cache-hook translation. |
| `8. Definition of Done` | `partial` | Core routing/middleware coverage now includes native adapters, retries, cache hooks, stream accumulation, JSON object helpers, and incremental object streaming. Remaining gaps are mostly around exhaustive multimodal/provider parity rather than missing primitives. |

## Verified Behaviors (with tests)

1. Provider routing by explicit/default provider.
2. Errors for missing/unregistered providers.
3. Middleware request transformation for complete and stream.
4. `complete_with_request/2` and `stream_with_request/2` return resolved requests.
5. Stream adapter dispatch and unsupported-stream error path.
6. Request field pass-through including reasoning/cache usage counters.
7. `from_env/1` runtime construction, retry-policy config, and module-level default client helpers.
8. Message-part content projection plus cache hints for richer request payloads.
9. Stream accumulation into a normalized final response.
10. JSON object decoding for non-streaming and streaming helper APIs.
11. Incremental `:object_delta` streaming for NDJSON/full-document streams.
12. Typed retry/error normalization with retryable adapter failures.
13. Native OpenAI, Anthropic, and Gemini request/stream translation coverage.

## Known Gaps vs Spec

1. Full content-part round-trip semantics across every provider-specific multimodal edge case remain incomplete even though the normalized message model and native adapters now carry richer parts.
2. Built-in tool-loop orchestration at unified client layer.
3. Prompt caching support is implemented as request hooks where providers expose a compatible surface, but not every provider offers identical cache semantics.
4. Provider compatibility coverage is focused on normalized translation and does not yet claim exhaustive upstream fixture parity.

## Verification Commands

```bash
mix test test/attractor_ex/llm_client_test.exs
mix precommit
```
