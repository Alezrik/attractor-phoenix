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
| `2. Agentic Loop` | `implemented` | Session lifecycle, loop rounds, natural completion, limits, steering/follow-up, loop detection, session/context event emission, and model-recoverable tool validation failures are covered. |
| `3. Provider-Aligned Toolsets` | `partial` | OpenAI/Anthropic/Gemini provider presets now bundle a shared baseline coding-agent toolset and capability metadata. Exact upstream per-provider tool parity and SDK-specific formatting are still not one-to-one. |
| `4. Tool Execution Environment` | `implemented` | `ExecutionEnvironment` now covers working directory, platform, file reads/writes, directory listing, globbing, grep, shell execution, and environment context, with `LocalExecutionEnvironment` implementing the contract. |
| `5. Tool Output and Context Management` | `implemented` | Character-first then line truncation, per-tool limits, timeout controls, and bounded event payload behavior are implemented/tested. |
| `6. System Prompts and Environment Context` | `implemented` | Layered prompt construction now includes provider/model metadata, platform, tool inventory, serialized environment context, and ancestor-discovered instruction docs (`AGENTS.md`, provider files, `.codex/instructions.md`) with custom builder hooks preserved. |
| `7. Subagents` | `implemented` | Session-managed `spawn_agent`, `send_input`, `wait`, and `close_agent` tools now create child sessions with independent history, shared execution environment, model/turn overrides, and enforced `max_subagent_depth`. |
| `8. Out of Scope` | `n/a` | Informational section. |
| `9. Definition of Done` | `partial` | Core loop behavior, baseline provider bundles, prompt context, local environment contract, and subagent lifecycle are covered. Exact provider-native parity remains open. |
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
11. Provider presets with built-in coding-agent tool bundles.
12. Execution-environment file/glob/grep/shell primitives.
13. Tool-argument schema validation and session/context warning events.
14. Ancestor-based project instruction discovery for prompt context.
15. Subagent lifecycle including spawn/input/wait/close flows, depth enforcement, and recoverable missing-agent errors.

## Known Gaps vs Spec

1. Provider-packaged toolsets are baseline-compatible, but not yet exact one-to-one mirrors of codex-rs, Claude Code, or gemini-cli.
2. Full event surface parity and cross-provider integration matrix.
3. Built-in `apply_patch` grammar enforcement utility as a first-class profile tool.

## Verification Commands

```bash
mix test test/attractor_ex/agent/primitives_test.exs test/attractor_ex/agent/session_test.exs
mix docs
mix precommit
```
