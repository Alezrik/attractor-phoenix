# Attractor Spec Compliance (AttractorEx)

This file tracks current compliance against the upstream Attractor specification.

## Source Documents

- Attractor spec: https://github.com/strongdm/attractor/blob/main/attractor-spec.md
- Repository: https://github.com/strongdm/attractor
- Upstream HEAD reviewed: `2f892efd63ee7c11f038856b90aae57c067b77c2` (checked 2026-03-06)

## Scope

Primary implementation:

1. `lib/attractor_ex/parser.ex`
2. `lib/attractor_ex/validator.ex`
3. `lib/attractor_ex/engine.ex`
4. `lib/attractor_ex/condition.ex`
5. `lib/attractor_ex/handlers/*.ex`

Primary tests:

1. `test/attractor_ex/dot_schema_test.exs`
2. `test/attractor_ex/parser_test.exs`
3. `test/attractor_ex/validator_test.exs`
4. `test/attractor_ex/condition_test.exs`
5. `test/attractor_ex/handlers_test.exs`
6. `test/attractor_ex/engine_test.exs`

## Section-by-Section Status

Legend: `implemented`, `partial`, `not implemented`.

| Upstream section | Status | Notes |
|---|---|---|
| `2. DOT DSL Schema` | `partial` | Supports directed graphs, attrs, chained edges, order-sensitive node/edge defaults, `strict digraph`, compact attr statements like `graph[...]` / `node[...]` / `edge[...]`, multi-line attr blocks including line-separated declarations inside `[...]`, repeated attr blocks like `[a=1][b=2]`, comma- and semicolon-separated attr declarations, class attr, shape mapping, bare / quoted / HTML-like graph and node identifiers (including bare graph ids with hyphens and numeric node ids), single/double-quoted attr values, value parsing including escaped newline/tab/carriage-return sequences in quoted strings, quote-aware statement splitting (so `;` and newlines inside quoted values are preserved), quote-aware comment stripping (so `//` and `/* */` inside quoted attr values are preserved), node-port edge endpoint parsing (`a:out -> b:in:nw`) with preserved `tailport` / `headport` attrs, and recursive inline/nested `subgraph` flattening with scoped default inheritance plus subgraph-label-derived classes, including subgraphs used directly as edge endpoints. Full Graphviz grammar parity is still not implemented. |
| `3. Pipeline Execution Engine` | `implemented` | Start-to-exit loop, edge selection priority, goal gates, retries/backoff, failure routing, loop restart, checkpoint/manifest/status artifacts, and the spec default `default_max_retry=50` behavior are implemented. |
| `4. Node Handlers` | `implemented` | Built-ins present: `start`, `exit`, `codergen`, `wait.human`, `conditional`, `parallel`, `parallel.fan_in`, `tool`, `stack.manager_loop`, default fallback. |
| `5. State and Context` | `implemented` | Context merge, `graph.*` context mirroring, `current_node` tracking, and per-node artifacts/checkpoints are implemented. First-class resume API is available via `AttractorEx.resume/3` using a checkpoint struct/map or `checkpoint.json` path. |
| `6. Human-in-the-Loop` | `implemented` | `wait.human` supports context-driven answers, timeout/default handling, blank-answer default routing, unmatched-answer fallback to the first outgoing choice, skip handling, single- and multi-select routing (`human.multiple`) with structured answer normalization, and interviewer abstractions (`AutoApprove`, `Console`, `Callback`, `Queue`, `Recording`, `Server`) via handler options. The interviewer behaviour includes optional `ask_multiple/4` and `inform/4` callbacks, the handler dispatches through `ask_multiple/4` when multi-select is enabled, all interviewer adapters share a normalized question contract (`FREEFORM` / `CONFIRMATION` / `YES_NO` / `MULTIPLE_CHOICE`) plus richer structured answer extraction (`answer` / `value` / `selected` / `answers` / `keys`) for single- and multi-select flows, the console interviewer surfaces prompt/default/timeout/input-mode metadata and accepts JSON-structured input, the recording interviewer captures normalized answer payloads, and the server interviewer exposes pending HTTP questions with normalized choice metadata (`multiple`, `required`, input mode, choice count), `human.required` / `human.input` metadata overrides, immediate pending-question registration before `InterviewStarted` is emitted, answer payload metadata on completion events, and day-based timeout suffix parsing (`1d`). |
| `7. Validation and Linting` | `implemented` | `Validator.validate/2` and `validate_or_raise/2` cover start/exit structure, edge source/target existence, condition parse errors, reachability errors, dead-end flow warnings, retry-target reference checks (including graph-level `retry_target` / `fallback_retry_target` attrs) using spec-aligned `retry_target_exists` lint metadata, graph-level retry-path reachability, retry-count linting (`default_max_retry`, node `max_retries`), goal-gate retry hints (without false-positive warnings when graph-level retry targets are defined), LLM-node prompt-or-label warnings for all nodes that resolve to the codergen handler, unknown explicit node types, fidelity value linting, stylesheet syntax errors, plus `wait.human` choice/default checks, prompt-presence lint, ambiguous default-choice lint, `human.multiple` / `human.required` / `human.input` attr linting, timeout/default lint (`human.timeout` without `human.default_choice`), timeout-format linting, duplicate human accelerator key warnings, codergen LLM attr lint checks (`reasoning_effort`, `temperature`, `max_tokens`, provider/model pairing), `parallel` attr linting (`join_policy`, `max_parallel`, `k`, `quorum_ratio`), `stack.manager_loop` attr linting (`manager.actions`, `manager.max_cycles`, `manager.poll_interval`, `stack.child_autostart`, autostart `stack.child_dotfile`), `allow_partial` boolean linting, stylesheet lint diagnostics, spec-aligned `rule` metadata on diagnostics, `validate/2` custom lint rule hooks, and `validate_or_raise/2` error escalation. Coverage is backed primarily by `validator_test.exs`, with public API checks in `attractor_ex_test.exs`. |
| `8. Model Stylesheet` | `implemented` | CSS-like `model_stylesheet` parsing is implemented (`*`, shape selectors like `box`, `.class`, `#id` with declaration blocks), including specificity ordering and same-specificity last-rule wins behavior, and is applied before validation while preserving explicit node attrs as the final override. Backward-compatible JSON stylesheet parsing remains supported, along with extended selector support (`type=...`, `node[type=...]`, `shape=...`, `node[shape=...]`, compound selectors, selector lists, dotted handler types like `wait.human`, and single-quoted selector values such as `node[type='wait.human']`). CSS declaration support covers codergen LLM attrs plus operational node attrs already used by the runtime (for example `timeout`, `prompt`, `command`, retry attrs, and `human.*` attrs including `human.multiple`, `human.required`, and `human.input`), both `:` and `=` declaration separators, `model` -> `llm_model` aliasing, quoted values (single/double quotes), escaped string content, CSS comments, quoted `/* ... */` comment markers, and quoted `;`/`}` characters inside declaration values. Invalid selectors are ignored during parse so lint can report them without turning valid CSS into a hard parse failure. Lint diagnostics cover unknown CSS properties, malformed declarations, invalid selectors, invalid CSS syntax, and invalid JSON-list/map rule shapes. |
| `9. Transforms and Extensibility` | `implemented` | Extensibility exists via handlers/backends/options. A graph transform pipeline is implemented via `run/resume` options (`graph_transforms` and legacy `graph_transform`) with function hooks plus module transforms supporting spec-style `apply/1` and backward-compatible `transform/1`, all applied after built-in transforms and before validation/execution. Built-in transforms cover stylesheet application, `$goal` variable expansion, and a runtime preamble transform that synthesizes context carryover text for non-`full` codergen stages based on fidelity settings. The optional HTTP server mode is available through `AttractorEx.start_http_server/1` with the section-9 core endpoint set: pipeline status, SSE events, cancellation, question/answer, checkpoint, context, plus graph responses in native SVG, raw DOT, parsed JSON, Mermaid flowchart text, and plain-text summaries. Definition-of-done compatibility aliases are also exposed via `POST /run`, `GET /status`, and `POST /answer`. The HTTP API rejects empty pipeline submissions, rejects unsupported graph formats with explicit `400` responses, returns explicit `413` JSON responses for oversized request bodies, applies `no-store`/`nosniff` response headers, and limits JSON request bodies to 1 MB by default. |
| `10. Condition Expression Language` | `implemented` | Equality/inequality, numeric comparisons, clause chaining, nil/boolean handling, nested context and `outcome` access are implemented and tested. |
| `11. Definition of Done` | `implemented` | Checklist coverage now includes the section-11.11 HTTP compatibility aliases (`POST /run`, `GET /status`, `POST /answer`) in addition to the broader `/pipelines/...` server contract, so the documented definition-of-done items are covered by parser, validator, engine, handler, interviewer, stylesheet, transform, and HTTP tests. |
| `Appendix A/B/C/D` | `partial` | Major attrs, shape mapping, status contract, and error categories are represented; not every appendix item is fully implemented. |

## Evidence Highlights

1. DOT parsing + schema: `dot_schema_test.exs` and `parser_test.exs` (including `strict digraph`, compact attr statements, quoted and HTML-like graph/node identifier coverage, bare graph ids with hyphens, numeric node ids, repeated attr blocks, line-/comma-/semicolon-separated attr declarations inside attr blocks, escaped newline/tab handling in quoted values, node port endpoint parsing, and subgraph edge endpoint expansion).
2. Validation diagnostics: `validator_test.exs` (start/exit structure, reachability including graph-level retry paths, condition syntax metadata, retry-target/default-max-retry linting, goal-gate retry lint behavior, `wait.human` prompt/default/timeout/choice checks, codergen/parallel/manager attr linting, stylesheet diagnostics, custom rules, diagnostic `rule` metadata, and `validate_or_raise/2` escalation) plus public wrapper coverage in `attractor_ex_test.exs`.
3. Engine routing/retry/goal-gate: `engine_test.exs`.
4. Condition language semantics: `condition_test.exs`.
5. Built-in handlers: `handlers_test.exs`.
6. Graph transform pipeline hooks, spec-style `apply/1` compatibility, built-in variable expansion, runtime preamble synthesis, and error handling: `engine_test.exs`.
7. CSS/JSON stylesheet parsing and parser handling of single/double-quoted string separators, escaped string content, quoted comment markers, CSS comments, shape selectors, `model=` aliasing, single-quoted selector values, dotted handler-type selectors, operational CSS attrs, and invalid selector diagnostics: `model_stylesheet_test.exs` and `parser_test.exs`.
8. Human interviewer adapters, recording wrapper, optional multi-select/inform callbacks, end-to-end `wait.human` multi-select routing, console prompt metadata, first-choice fallback for unmatched answers, and server-side question-type inference / structured metadata / answer normalization including `human.required` / `human.input` overrides, day-duration timeout parsing, and immediate pending-question visibility for short-timeout server questions: `handlers_test.exs`, `interviewers_test.exs`, and `interviewer_server_test.exs`.
9. HTTP server mode, SSE events, pending question flow, answer submission, native SVG/DOT/JSON/Mermaid/plain-text graph variants, definition-of-done compatibility aliases (`POST /run`, `GET /status`, `POST /answer`), invalid-request handling, and pending-question metadata exposure for `wait.human`: `http_test.exs`.

## Known Gaps vs Spec

1. Full Graphviz DOT grammar parity remains incomplete beyond the supported runtime-oriented subset (for example full HTML-string grammar fidelity, richer endpoint forms and attr_stmt variants, and unsupported constructs that do not map cleanly into AttractorEx execution semantics).
## Verification Commands

```bash
mix test test/attractor_ex/dot_schema_test.exs
mix test test/attractor_ex/parser_test.exs test/attractor_ex/validator_test.exs
mix test test/attractor_ex/condition_test.exs test/attractor_ex/handlers_test.exs test/attractor_ex/engine_test.exs
mix test test/attractor_ex/interviewer_server_test.exs
mix test test/attractor_ex/http_test.exs
mix precommit
```
