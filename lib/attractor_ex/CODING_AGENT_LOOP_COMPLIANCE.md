# Coding Agent Loop Spec Compliance (AttractorEx)

This document records how `AttractorEx.Agent.Session` and related modules map to the upstream strongDM coding-agent-loop behavior and where that behavior is validated by tests.

## Scope

Implementation scope:

1. `lib/attractor_ex/agent/session.ex`
2. `lib/attractor_ex/agent/session_config.ex`
3. `lib/attractor_ex/agent/provider_profile.ex`
4. `lib/attractor_ex/agent/tool*.ex`

Primary verification tests:

1. `test/attractor_ex/agent/session_test.exs`
2. `test/attractor_ex/agent/primitives_test.exs`

## Compliance Matrix

### Session lifecycle and loop execution

1. Session states (`:idle`, `:processing`, `:awaiting_input`, `:closed`) and state transitions are implemented in `Session` (`new`, `submit`, `close`, `abort`).
2. Per-input processing runs iterative request/tool rounds through `run_rounds/2`.
3. `session_end` is emitted after each completed submit cycle.

Tests:

- `natural completion when response has no tool calls`
- `returns unchanged session for submit when state is closed`
- `abort marks session as closed`
- `abort_signaled short-circuits tool loop execution`

### Tool-call execution flow

1. Tool call payload normalization supports struct, atom-keyed map, and string-keyed map forms.
2. Tool arguments support map inputs and JSON-string decoding fallback.
3. Unknown tools are converted to structured error tool results and surfaced to the model in the next round.
4. Tool lifecycle emits `:tool_call_start` / `:tool_call_end` events.

Tests:

- `runs tool round and then finishes`
- `handles string-keyed tool call maps from provider payloads`
- `handles atom-keyed tool call maps`
- `parses JSON string arguments for tool calls`
- `falls back to empty map when tool arguments are invalid JSON`
- `falls back to empty map when tool arguments are non-map non-binary`
- `unknown tool returns error result and model can recover`

### Steering, follow-up, and history wiring

1. Steering messages are queued and injected into history before model calls.
2. Follow-up prompts are queued and executed after current input cycle completion.
3. History is serialized into chat messages across `user`, `assistant`, `system`, `steering`, and `tool_results` turns.

Tests:

- `steering message is injected before processing`
- `follow_up runs after current input completes`

### Loop and turn-limit controls

1. Global turn cap (`max_turns`) is supported.
2. Tool round cap (`max_tool_rounds_per_input`) is supported.
3. Loop detection is supported via repeated round-signature matching.
4. Loop detection emits steering feedback and ends the current processing cycle.

Tests:

- `loop detection emits warning when identical tool call repeats`
- `loop detection terminates current processing cycle`
- `batched repeated tool calls in one round do not trigger loop detection`
- `max turns emits limit event`
- `max tool rounds emits limit event`
- `max tool rounds still allows post-tool assistant completion`

### Parallel tool calls

1. Parallel tool dispatch uses `Task.async_stream/3` when provider profile allows it.
2. Task exits are transformed into tool error results.

Tests:

- `parallel tool calls execute concurrently when profile allows it`

### Timeouts, truncation, and failure handling

1. Tool execution timeout is enforced with per-call override for `shell_command.timeout_ms` capped by config max.
2. Tool output truncation enforces both character and optional line budgets.
3. Timeout path drains late worker messages to avoid mailbox growth.
4. Tool failures from raise/throw/exit are captured as error tool results.
5. LLM completion errors are recorded and close the session.

Tests:

- `tool execution times out using default session timeout`
- `shell timeout_ms argument overrides default timeout within max cap`
- `invalid shell timeout argument falls back to default timeout`
- `late tool reply after timeout is treated as timeout`
- `repeated tool timeouts do not accumulate mailbox messages`
- `repeated tool timeouts do not leave stale messages after final run`
- `tool output truncation applies character and line limits`
- `character truncation never exceeds configured limit`
- `line truncation fallback keeps original output when limit is not integer`
- `line truncation still respects final character limit`
- `tool_call_end event output is bounded by truncation limit`
- `records tool errors when tool raises`
- `records tool errors when tool throws`
- `records tool errors when tool exits`
- `closes session on llm error`
- `llm error does not drop queued follow-up input`

### Prompt/context wiring

1. System prompt is composed from provider profile plus environment metadata.
2. Project guidance files are discovered in the working directory (`AGENTS.md` and provider-specific docs).
3. Reasoning effort defaults to `"high"` and supports override.

Tests:

- `uses high reasoning effort by default`
- `uses configured reasoning effort override`
- `uses cwd fallback when execution env is not local env struct`

## Verification Commands

```bash
mix test test/attractor_ex/agent/primitives_test.exs test/attractor_ex/agent/session_test.exs
mix precommit
```

## Upstream Spec Link

- https://github.com/strongdm/attractor/blob/main/coding-agent-loop-spec.md

Keep this document in sync with any upstream loop-spec changes and add/adjust tests first before implementation changes.
