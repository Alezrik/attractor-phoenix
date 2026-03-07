# AttractorEx (Standalone Library)

`AttractorEx` is the primary artifact in this repository.

This folder contains a DOT-driven pipeline engine inspired by strongDM Attractor:

1. Parser (`Parser`)
2. Validator (`Validator`)
3. Execution engine (`Engine`)
4. Routing and condition evaluator (`Condition`)
5. Handler registry + built-in handlers (`Handlers.*`)

## Independence from Phoenix App

`lib/attractor_ex` does not depend on `AttractorPhoenix` or `AttractorPhoenixWeb` modules.

Dependency boundary:

1. Internal references are only `AttractorEx.*`.
2. Runtime deps used here are standard library + `Jason`.
3. Phoenix is used by the demo UI app, not by this library code.

## Public API

```elixir
AttractorEx.run(dot_source, context_map, opts)
```

Example:

```elixir
dot = """
digraph attractor {
  start [shape=Mdiamond]
  hello [shape=parallelogram, tool_command="echo hello world"]
  done [shape=Msquare]
  start -> hello
  hello -> done
}
"""

{:ok, result} = AttractorEx.run(dot, %{})
```

## Configuring LLM Nodes (`codergen`)

`AttractorEx` treats `box` nodes (or `type="codergen"`) as LLM stages.

Handler behavior:

1. Prompt source: node `prompt` (fallback: node `label`).
2. Variable expansion: `$goal` from graph-level `goal`.
3. Preferred backend selection: `opts[:llm_client]` using unified LLM client.
4. Legacy backend selection: `opts[:codergen_backend]`.
5. Legacy backend contract: module with `run(node, prompt, context)` returning:
   - `String` (will be written to `response.md`), or
   - `%AttractorEx.Outcome{}` (full control of status/context updates).

Unified client contract:

1. Build client with providers map and optional default:
   - `%AttractorEx.LLM.Client{providers: %{"openai" => MyAdapter}, default_provider: "openai"}`
2. Adapter module contract:
   - `complete(%AttractorEx.LLM.Request{}) :: %AttractorEx.LLM.Response{} | {:error, term()}`
3. Node attrs used for unified request:
   - `llm_model`, `llm_provider`, `reasoning_effort`, `max_tokens`, `temperature`

Example backend module:

```elixir
defmodule MyApp.LLMBackend do
  alias AttractorEx.Outcome

  def run(node, prompt, _context) do
    # Call your LLM provider here.
    text = "Response for #{node.id}: #{prompt}"
    Outcome.success(%{"responses" => %{node.id => text}}, "LLM completed")
  end
end
```

Run with backend:

```elixir
AttractorEx.run(dot_source, %{}, codergen_backend: MyApp.LLMBackend)
```

Run with unified client:

```elixir
llm_client = %AttractorEx.LLM.Client{
  providers: %{"openai" => MyAdapter},
  default_provider: "openai"
}

AttractorEx.run(dot_source, %{}, llm_client: llm_client)
```

Artifacts written by codergen stage:

1. `prompt.md`
2. `response.md`
3. `status.json`


## Coding Agent Loop Spec Compliance

Coding-agent loop behavior is implemented in the Agent session modules and tracked in:

1. `lib/attractor_ex/CODING_AGENT_LOOP_COMPLIANCE.md`
2. Source spec: https://github.com/strongdm/attractor/blob/main/coding-agent-loop-spec.md

Unified LLM behavior is tracked in:

1. `lib/attractor_ex/UNIFIED_LLM_SPEC_COMPLIANCE.md`
2. Source spec: https://github.com/strongdm/attractor/blob/main/unified-llm-spec.md

Core Attractor engine behavior is tracked in:

1. `lib/attractor_ex/ATTRACTOR_SPEC_COMPLIANCE.md`
2. Source spec: https://github.com/strongdm/attractor/blob/main/attractor-spec.md

These compliance docs use `implemented` / `partial` / `not implemented` status per upstream section and should be updated whenever upstream spec content changes.

## How to Extract into Another Project

1. Copy `lib/attractor_ex/` into your project under `lib/`.
2. Copy `lib/attractor_ex.ex` (public entrypoint module).
3. Add `{:jason, "~> 1.2"}` to dependencies (if not already present).
4. Copy `test/attractor_ex/` tests (recommended) and run them.

Optional: copy `test/support/attractor_ex_test_*` backend fixtures for spec-style test scenarios.

## Verification Commands

```bash
mix test test/attractor_ex
mix coveralls
```

Coverage is configured to enforce a 90% minimum for AttractorEx scope.

## Spec Reference

1. https://github.com/strongdm/attractor
2. https://github.com/strongdm/attractor/blob/main/attractor-spec.md
3. https://github.com/strongdm/attractor/blob/main/coding-agent-loop-spec.md
4. https://github.com/strongdm/attractor/blob/main/unified-llm-spec.md
5. Local compliance docs:
   - `lib/attractor_ex/ATTRACTOR_SPEC_COMPLIANCE.md`
   - `lib/attractor_ex/CODING_AGENT_LOOP_COMPLIANCE.md`
   - `lib/attractor_ex/UNIFIED_LLM_SPEC_COMPLIANCE.md`
6. Baseline commit currently implemented/tested against:
   `2f892efd63ee7c11f038856b90aae57c067b77c2` (verified 2026-03-06)

## Keeping Up with Upstream

1. Refresh local reference clone: `git -C ..\\_attractor_reference fetch --all --prune`
2. Compare baseline: `git -C ..\\_attractor_reference rev-parse HEAD`
3. If changed, review spec diff and update `AttractorEx` tests first, then implementation.
