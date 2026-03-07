# Coding Agent Loop Spec Compliance (AttractorEx)

This file maps `AttractorEx.Agent.*` behavior to the upstream coding-agent-loop specification.

## Source Documents

- Coding-agent loop spec: https://github.com/strongdm/attractor/blob/main/coding-agent-loop-spec.md
- Related unified LLM spec: https://github.com/strongdm/attractor/blob/main/unified-llm-spec.md
- Upstream HEAD reviewed: `2f892efd63ee7c11f038856b90aae57c067b77c2` (checked 2026-03-06)

## Scope

Implementation:

1. `lib/attractor_ex/agent/session.ex`
2. `lib/attractor_ex/agent/session_config.ex`
3. `lib/attractor_ex/agent/provider_profile.ex`
4. `lib/attractor_ex/agent/tool.ex`
5. `lib/attractor_ex/agent/tool_registry.ex`
6. `lib/attractor_ex/agent/execution_environment.ex`
7. `lib/attractor_ex/agent/local_execution_environment.ex`

Tests:

1. `test/attractor_ex/agent/session_test.exs`
2. `test/attractor_ex/agent/primitives_test.exs`

## Section-by-Section Status

Legend: `implemented`, `partial`, `not implemented`.

| Upstream section | Status | Notes |
|---|---|---|
| `2. Agentic Loop` | `implemented` | Session lifecycle, loop rounds, natural completion, limits, steering/follow-up, loop detection, event emission are covered. |
| `3. Provider-Aligned Toolsets` | `partial` | Generic tool/profile model exists. Full OpenAI/Anthropic/Gemini profile bundles and spec-level parity are not fully implemented in this library. |
| `4. Tool Execution Environment` | `partial` | Abstraction exists, but current environment interface is minimal (`working_directory`, `platform`) vs full file/command contract in spec. |
| `5. Tool Output and Context Management` | `implemented` | Character-first then line truncation, per-tool limits, timeout controls, and bounded event payload behavior are implemented/tested. |
| `6. System Prompts and Environment Context` | `partial` | Layered prompt with environment/doc discovery and provider builder hooks exists, but not all spec context fields and provider-specific doc loading behavior are fully implemented. |
| `7. Subagents` | `not implemented` | No spawn/send/wait/close subagent tooling in current code. |
| `8. Out of Scope` | `n/a` | Informational section. |
| `9. Definition of Done` | `partial` | Large coverage for core loop/tool behavior; provider parity, full environment contract, and subagents remain open. |
| `Appendix A (apply_patch v4a)` | `not implemented` | Spec appendix documented upstream; no built-in parser/enforcer module here. |
| `Appendix B (error handling)` | `partial` | Tool/session error propagation and recovery behaviors are implemented, but full cross-provider SDK retry hierarchy is delegated to Unified LLM layer. |

## Verified Behaviors (with tests)

1. Session lifecycle and closure/abort behavior.
2. Tool call normalization and robust argument parsing.
3. Unknown tool error results (model-recoverable).
4. Steering and follow-up sequencing.
5. Loop detection and turn/tool-round limits.
6. Parallel tool call execution when enabled by profile.
7. Timeout handling including late message drainage.
8. Character+line truncation behavior and bounded event output.
9. Tool failure capture (`raise`/`throw`/`exit`) and LLM error shutdown.
10. Reasoning effort default/override and working-dir fallback logic.

## Known Gaps vs Spec

1. Provider-packaged toolsets aligned exactly to codex-rs, Claude Code, gemini-cli.
2. Rich execution environment contract (full FS/command APIs and env filtering behaviors as spec defines).
3. Subagent lifecycle and related tools (`spawn_agent`, `send_input`, `wait`, `close_agent`).
4. Full event surface parity and cross-provider integration matrix.
5. Built-in apply_patch grammar enforcement utility as a first-class profile tool.

## Verification Commands

```bash
mix test test/attractor_ex/agent/primitives_test.exs test/attractor_ex/agent/session_test.exs
mix precommit
```
