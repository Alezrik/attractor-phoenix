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
3. Phoenix-specific integration now lives in the separate `AttractorExPhx` adapter layer.
4. Phoenix is used by the demo UI app, not by this library code.

## Public API

```elixir
AttractorEx.run(dot_source, context_map, opts)
AttractorEx.resume(dot_source, checkpoint_or_path, opts)
AttractorEx.start_http_server(port: 4041)
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

checkpoint_path = Path.join(result.logs_root, "checkpoint.json")
{:ok, resumed} = AttractorEx.resume(dot, checkpoint_path, codergen_backend: MyApp.LLMBackend)

{:ok, server_pid} = AttractorEx.start_http_server(port: 4041)
```

## HTTP Server Mode

`AttractorEx.start_http_server/1` starts a lightweight Bandit-backed HTTP service around the engine.

Implemented endpoints:

1. `POST /pipelines`
2. `GET /pipelines/:id`
3. `GET /pipelines/:id/events`
4. `POST /pipelines/:id/cancel`
5. `GET /pipelines/:id/graph`
6. `GET /pipelines/:id/questions`
7. `POST /pipelines/:id/questions/:qid/answer`
8. `GET /pipelines/:id/checkpoint`
9. `GET /pipelines/:id/context`

Compatibility aliases for the definition-of-done checklist:

1. `POST /run` delegates to `POST /pipelines`
2. `GET /status?pipeline_id=...` (or `?id=...`) delegates to `GET /pipelines/:id`
3. `POST /answer` accepts `pipeline_id`, `question_id` (or `qid`), and `answer` (or `value`)

Graph endpoint formats:

1. Default: `GET /pipelines/:id/graph` returns a native SVG graph rendering.
2. `GET /pipelines/:id/graph?format=dot` returns raw DOT.
3. `GET /pipelines/:id/graph?format=json` returns parsed graph JSON.
4. `GET /pipelines/:id/graph?format=mermaid` returns Mermaid flowchart text.
5. `GET /pipelines/:id/graph?format=text` returns a plain-text graph summary.

HTTP service hardening:

1. Empty pipeline submissions are rejected with `400`.
2. Unsupported graph formats are rejected with `400` and a supported-format list.
3. Responses include `cache-control: no-store` and `x-content-type-options: nosniff`.
4. JSON request parsing is limited to a 1 MB body by default.

Human-in-the-loop web flow:

1. Submit a pipeline containing `wait.human`.
2. Poll `GET /pipelines/:id/questions` for pending questions.
3. Send a choice to `POST /pipelines/:id/questions/:qid/answer`.
4. Subscribe to `GET /pipelines/:id/events` for SSE status updates.

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
   - or `AttractorEx.LLM.Client.from_env/1` with:

     ```elixir
     config :attractor_phoenix, :attractor_ex_llm,
       providers: %{"openai" => MyAdapter},
       default_provider: "openai"
     ```
2. Adapter module contract:
   - `complete(%AttractorEx.LLM.Request{}) :: %AttractorEx.LLM.Response{} | {:error, term()}`
3. Node attrs used for unified request:
   - `llm_model`, `llm_provider`, `reasoning_effort`, `max_tokens`, `temperature`
4. Higher-level client helpers:
   - `generate/2` and `generate_with_request/2`
   - `accumulate_stream/2` to turn raw streaming events into a final `%AttractorEx.LLM.Response{}`
   - `generate_object/2` and `stream_object/2` for JSON object decoding
5. Message content:
   - `AttractorEx.LLM.Message.content` accepts either plain text or a list of `AttractorEx.LLM.MessagePart` structs for richer multimodal/tool/thinking payloads

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

Default-client helpers are also available for applications that want a process-wide
singleton:

```elixir
client = AttractorEx.LLM.Client.from_env()
AttractorEx.LLM.Client.put_default(client)

response =
  AttractorEx.LLM.Client.generate(%AttractorEx.LLM.Request{
    model: "gpt-5.2",
    messages: [%AttractorEx.LLM.Message{role: :user, content: "Plan the change"}]
  })
```

Artifacts written by codergen stage:

1. `prompt.md`
2. `response.md`
3. `status.json`

`status.json` follows the Appendix C contract:

1. `outcome`
2. `preferred_next_label`
3. `suggested_next_ids`
4. `context_updates`
5. `notes`

Backward-compatible aliases such as `status` and `preferred_label` are still emitted.


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

Current coding-agent highlights:

1. `ProviderProfile.openai/1`, `ProviderProfile.anthropic/1`, and `ProviderProfile.gemini/1` now expose provider-aligned tool bundles and capability metadata instead of a single shared tool list. OpenAI includes `apply_patch`, Anthropic and Gemini include `edit_file`, and Gemini also includes `read_many_files` plus `list_dir`, with opt-in `web_search`/`web_fetch` support via `ProviderProfile.gemini(web_tools: true)`.
2. `AttractorEx.Agent.LocalExecutionEnvironment` now exposes file IO, directory listing, globbing, grep, shell execution, and environment metadata through the `ExecutionEnvironment` behaviour.
3. `AttractorEx.Agent.ApplyPatch` backs the OpenAI-facing `apply_patch` tool for local sessions, handling add/delete/update/move operations in the appendix-style patch envelope.
4. `AttractorEx.Agent.Session` validates object-style tool arguments, emits spec-style typed session events (including synthesized assistant text deltas and full-output `tool_call_end` host events), layers ancestor project instruction files such as `AGENTS.md`, `CODEX.md`, and `.codex/instructions.md` into the default prompt context under a shared 32 KB budget, and manages spec-style subagent tools (`spawn_agent`, `send_input`, `wait`, `close_agent`) with depth limits.
5. `AttractorEx.Agent.ProviderProfile` exposes provider-specific base prompt guidance, supports deterministic custom-tool registration/override via `register_tool/2` and `register_tools/2`, and publishes a maintained OpenAI/Anthropic/Gemini compatibility matrix covering implemented tool names, reference tool names, capability flags, instruction files, reasoning-option paths, and shared event kinds.

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
