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
4. `lib/attractor_ex/agent/builtin_tools.ex`
5. `lib/attractor_ex/agent/apply_patch.ex`
6. `lib/attractor_ex/agent/tool.ex`
7. `lib/attractor_ex/agent/tool_registry.ex`
8. `lib/attractor_ex/agent/execution_environment.ex`
9. `lib/attractor_ex/agent/local_execution_environment.ex`

Tests:

1. `test/attractor_ex/agent/session_test.exs`
2. `test/attractor_ex/agent/primitives_test.exs`
3. `test/attractor_ex/agent/builtin_tools_test.exs`

## Section-by-Section Status

Legend: `implemented`, `partial`, `not implemented`.

| Upstream section | Status | Notes |
|---|---|---|
| `2. Agentic Loop` | `implemented` | Session lifecycle, loop rounds, natural completion, limits, steering/follow-up, loop detection, spec-style session event emission, full-output tool-call host events, and model-recoverable tool validation failures are covered. |
| `3. Provider-Aligned Toolsets` | `partial` | OpenAI/Anthropic/Gemini presets now expose provider-specific tool bundles and capability flags, including OpenAI `apply_patch`, Anthropic/Gemini `edit_file`, Gemini `read_many_files`/`list_dir`, and provider-native `shell` naming. Byte-for-byte upstream prompt/tool parity and optional Gemini web tools remain open. |
| `4. Tool Execution Environment` | `implemented` | `ExecutionEnvironment` now covers working directory, platform, file reads/writes, directory listing, globbing, grep, shell execution, and environment context, with `LocalExecutionEnvironment` implementing the contract. |
| `5. Tool Output and Context Management` | `implemented` | Character-first then line truncation, per-tool limits, timeout controls, and bounded event payload behavior are implemented/tested. |
| `6. System Prompts and Environment Context` | `implemented` | Layered prompt construction now includes provider/model metadata, platform, tool inventory, serialized environment context, and ancestor-discovered instruction docs (`AGENTS.md`, provider files, `.codex/instructions.md`) with custom builder hooks preserved. |
| `7. Subagents` | `implemented` | Session-managed `spawn_agent`, `send_input`, `wait`, and `close_agent` tools now create child sessions with independent history, shared execution environment, model/turn overrides, and enforced `max_subagent_depth`. |
| `8. Out of Scope` | `n/a` | Informational section. |
| `9. Definition of Done` | `partial` | Core loop behavior, provider-specific tool bundles, prompt context, local environment contract, and subagent lifecycle are covered. Exact provider-native prompt parity and the remaining optional provider tools remain open. |
| `Appendix A (apply_patch v4a)` | `partial` | A built-in `apply_patch` tool now parses and applies add/delete/update/move operations in the appendix-style envelope for local sessions. Full appendix-edge-case coverage and exhaustive parity validation remain open. |
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
10. Spec-aligned session event surface including `assistant_text_start`, `assistant_text_delta`, `tool_call_output_delta`, `error`, and full untruncated `tool_call_end` payloads for host integrations.
11. Reasoning effort default/override and working-dir fallback logic.
12. Provider presets with provider-specific coding-agent tool bundles, capability flags, and a maintained OpenAI/Anthropic/Gemini integration matrix.
13. Execution-environment file/glob/grep/shell primitives.
14. Tool-argument schema validation and session/context warning events.
15. Ancestor-based project instruction discovery for prompt context.
16. Subagent lifecycle including spawn/input/wait/close flows, depth enforcement, and recoverable missing-agent errors.
17. OpenAI-style `apply_patch` execution for local sessions plus Anthropic/Gemini-native edit/read-many/list-dir tool variants.

## Known Gaps vs Spec

1. Provider-packaged toolsets are closer to codex-rs, Claude Code, and gemini-cli, but are not yet byte-for-byte harness copies.
2. Gemini's optional `web_search` and `web_fetch` tools are still not built in.
3. `apply_patch` coverage is intentionally conservative and not yet validated against every appendix edge case.

## Verification Commands

```bash
mix test test/attractor_ex/agent/primitives_test.exs test/attractor_ex/agent/session_test.exs
mix docs
mix precommit
```
