# Agent Loop

`AttractorEx.Agent.*` implements a spec-inspired coding-agent session model on top of the unified LLM client.

## Main Modules

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
- tool definitions
- provider options
- a system prompt builder

This keeps the agent loop portable across LLM providers while letting each integration choose its own prompt and tool behavior.

## Execution Environment

The current environment contract is intentionally minimal:

- `working_directory/1`
- `platform/1`

`AttractorEx.Agent.LocalExecutionEnvironment` is the default implementation used in tests and local sessions.

## Compliance Status

The local coding-agent compliance guide tracks implemented and missing areas relative to the upstream coding-agent loop specification. Read the `Coding Agent Loop Compliance` reference for the detailed matrix.
