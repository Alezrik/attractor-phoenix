# 05. Conformance And Proof

This workstream exists to make the project's claims provable, not just plausible.

Primary inspiration:

1. `TheFellow-fkyeah` for black-box conformance discipline
2. `smartcomputer-ai-forge` for conformance decomposition and gap-management rigor
3. `aliciapaz-attractor-rb` for readable divergence tracking

## Goal

Build and maintain a benchmark-grade black-box conformance suite with a visible scoreboard tied to executable evidence.

## Implemented Surface

The repository now exposes a dedicated conformance harness in `test/attractor_ex/conformance/` with one suite per domain:

1. `parsing_conformance_test.exs`
2. `runtime_conformance_test.exs`
3. `state_conformance_test.exs`
4. `transport_conformance_test.exs`
5. `agent_loop_conformance_test.exs`
6. `unified_llm_conformance_test.exs`

Shared fixture data for those suites lives in `test/support/attractor_ex_conformance_fixtures.ex`.

The published scoreboard is maintained in `AttractorPhoenix.Conformance` and rendered on the LiveView benchmark page at `/benchmark`.

## Benchmark Matrix

Current black-box scorecard:

| Domain | Score | Evidence |
| --- | ---: | --- |
| Parsing | `4.5` | `mix test test/attractor_ex/conformance/parsing_conformance_test.exs` |
| Runtime | `4.0` | `mix test test/attractor_ex/conformance/runtime_conformance_test.exs` |
| State | `3.5` | `mix test test/attractor_ex/conformance/state_conformance_test.exs` |
| Transport | `4.0` | `mix test test/attractor_ex/conformance/transport_conformance_test.exs` |
| Agent loop | `4.0` | `mix test test/attractor_ex/conformance/agent_loop_conformance_test.exs` |
| Unified LLM | `4.0` | `mix test test/attractor_ex/conformance/unified_llm_conformance_test.exs` |

Composite conformance score: `4.0`

## Verification Commands

Run the public proof surface with:

```bash
mix test test/attractor_ex/conformance
mix test test/attractor_ex/http_test.exs
mix test test/attractor_ex/agent/session_test.exs
mix test test/attractor_ex/llm_client_test.exs
```

The first command is the benchmark-facing harness. The remaining focused suites provide deeper supporting evidence for areas still marked `partial`.

## Gap Ledger

Known proof gaps remain public and explicit:

1. `CONF-STATE-001`
   The file-backed HTTP manager proves restart persistence, but a wider cold-boot durability benchmark is still a runtime-foundation item.
   Evidence: `test/attractor_ex/conformance/state_conformance_test.exs`
   Roadmap: `docs/plan/02-runtime-foundation.md`
2. `CONF-TRANSPORT-001`
   The benchmark harness covers create/status/questions/answers, but SSE replay remains covered by focused transport tests rather than this compact scoreboard suite.
   Evidence: `test/attractor_ex/http_test.exs`
   Roadmap: `docs/plan/03-operator-surface-and-debugger.md`
3. `CONF-AGENT-001`
   The benchmark harness proves the default provider preset and event surface, but deeper multi-provider/subagent matrices still live in focused session tests.
   Evidence: `test/attractor_ex/agent/session_test.exs`
   Roadmap: `docs/plan/06-unified-llm-and-agent-platform.md`
4. `CONF-LLM-001`
   The scoreboard proves provider-agnostic JSON and stream normalization, while provider-native parity gaps remain tracked in the unified LLM compliance matrix.
   Evidence: `test/attractor_ex/conformance/unified_llm_conformance_test.exs`
   Roadmap: `docs/plan/06-unified-llm-and-agent-platform.md`

## Success Criteria

This workstream is considered implemented when:

1. implementation claims can be traced to executable tests
2. the repo exposes a public benchmark or conformance scorecard
3. partial or missing areas are documented explicitly, not implied away
4. the proof surface is maintained alongside the benchmark page and published docs
