# Agent Loop

`AttractorEx.Agent.*` implements a spec-inspired coding-agent session model on top of the unified LLM client.

## Main Modules

- `AttractorEx.Agent.BuiltinTools`
- `AttractorEx.Agent.Session`
- `AttractorEx.Agent.SessionConfig`
- `AttractorEx.Agent.ProviderProfile`
- `AttractorEx.Agent.Tool`
- `AttractorEx.Agent.ToolCall`
- `AttractorEx.Agent.ToolResult`
- `AttractorEx.Agent.ToolRegistry`
- `AttractorEx.Agent.ExecutionEnvironment`
- `AttractorEx.Agent.LocalExecutionEnvironment`

## Responsibilities

`AttractorEx.Agent.Session` owns the loop:

1. build a provider-aligned request
2. send it through `AttractorEx.LLM.Client`
3. normalize tool calls
4. execute tools with timeouts and truncation rules
5. feed tool results back into the next round

The session layer is deliberately conservative: it focuses on determinism, bounded output, and operational safety rather than full parity with every upstream provider feature.

## Event Surface

`AttractorEx.Agent.Session` now emits a typed event stream through `AttractorEx.Agent.Event`.

Implemented event kinds include:

- `session_start`
- `session_end`
- `user_input`
- `assistant_text_start`
- `assistant_text_delta`
- `assistant_text_end`
- `tool_call_start`
- `tool_call_output_delta`
- `tool_call_end`
- `steering_injected`
- `turn_limit`
- `loop_detection`
- `error`

For non-streaming `Client.complete/2` responses and synchronous tool execution, the session synthesizes single-chunk delta events so host applications can still consume a consistent event surface. `tool_call_end` carries the full untruncated tool output for UI/logging integrations, while the model continues to receive the bounded/truncated tool result stored in conversation history.

## Provider Profiles

`AttractorEx.Agent.ProviderProfile` packages:

- a provider ID
- a model name
- provider capability metadata such as parallel tool-call support and context-window size
- tool definitions
- provider options
- a system prompt builder

This keeps the agent loop portable across LLM providers while letting each integration choose its own prompt and tool behavior.

Convenience presets are available for the common coding-agent providers:

- `ProviderProfile.openai/1`
- `ProviderProfile.anthropic/1`
- `ProviderProfile.gemini/1`

Those presets attach the built-in agent tool bundle and default capability metadata so applications do not need to rebuild the baseline profile shape manually.

`ProviderProfile.integration_matrix/0` exposes the maintained cross-provider compatibility matrix for:

- implemented tool names
- upstream reference tool names
- provider-specific instruction files
- reasoning/thinking option paths
- shared session event kinds

## Execution Environment

The environment contract now includes the local tool surface used by the coding-agent loop:

- `working_directory/1`
- `platform/1`
- `read_file/2`
- `write_file/3`
- `list_directory/2`
- `glob/2`
- `grep/3`
- `shell_command/3`
- `environment_context/1`

`AttractorEx.Agent.LocalExecutionEnvironment` is the default implementation used in tests and local sessions.

## Built-In Tools

`AttractorEx.Agent.BuiltinTools` exposes a provider-neutral baseline toolset:

- `read_file`
- `write_file`
- `list_directory`
- `glob`
- `grep`
- `shell_command`
- `spawn_agent`
- `send_input`
- `wait`
- `close_agent`

Filesystem and shell tools are backed by the execution-environment behaviour, so alternative environments can swap in sandboxed or remote implementations without changing the session loop. Subagent tools are session-managed and create child `AttractorEx.Agent.Session` instances that keep independent history while sharing the parent's execution environment.

## Subagents

The coding-agent loop now implements the spec's subagent lifecycle:

- `spawn_agent` creates a child session, inherits the parent profile/tool bundle, optionally overrides model, working directory, and `max_turns`, and immediately runs the scoped task
- `send_input` continues an existing child session with another message
- `wait` returns a JSON payload containing subagent output, success, and turns used
- `close_agent` removes the child session from the active subagent map

Subagents inherit the parent's execution environment and are depth-limited by `SessionConfig.max_subagent_depth` (default `1`).

## Prompt Context

The default system-prompt builder now includes:

- working directory and platform
- provider/model metadata
- available tool names
- serialized environment context
- project instruction files discovered from the working directory ancestry

Project instruction discovery loads `AGENTS.md` plus provider-specific files such as `CODEX.md`, `CLAUDE.md`, `GEMINI.md`, and `.codex/instructions.md` when present.

## Compliance Status

The local coding-agent compliance guide tracks implemented and missing areas relative to the upstream coding-agent loop specification. Read the `Coding Agent Loop Compliance` reference for the detailed matrix.
