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

These tools are backed by the execution-environment behaviour, so alternative environments can swap in sandboxed or remote implementations without changing the session loop.

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
