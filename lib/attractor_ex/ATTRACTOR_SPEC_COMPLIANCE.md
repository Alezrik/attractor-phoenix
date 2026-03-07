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
| `2. DOT DSL Schema` | `partial` | Supports directed graphs, attrs, chained edges, order-sensitive node/edge defaults, multi-line attr blocks, class attr, shape mapping, quoted node identifiers, value parsing, quote-aware statement splitting (so `;` and newlines inside quoted values are preserved), quote-aware comment stripping (so `//` and `/* */` inside quoted attr values are preserved), and recursive inline/nested `subgraph` flattening with scoped default inheritance plus subgraph-label-derived classes. Full grammar coverage is not fully implemented. |
| `3. Pipeline Execution Engine` | `implemented` | Start-to-exit loop, edge selection priority, goal gates, retries/backoff, failure routing, loop restart, checkpoint/manifest/status artifacts, and the spec default `default_max_retry=50` behavior are implemented. |
| `4. Node Handlers` | `implemented` | Built-ins present: `start`, `exit`, `codergen`, `wait.human`, `conditional`, `parallel`, `parallel.fan_in`, `tool`, `stack.manager_loop`, default fallback. |
| `5. State and Context` | `implemented` | Context merge, `graph.*` context mirroring, `current_node` tracking, and per-node artifacts/checkpoints are implemented. First-class resume API is available via `AttractorEx.resume/3` using a checkpoint struct/map or `checkpoint.json` path. |
| `6. Human-in-the-Loop` | `partial` | `wait.human` supports context-driven answers, timeout/default handling, blank-answer default routing, unmatched-answer fallback to the first outgoing choice, skip handling, and interviewer abstractions (`AutoApprove`, `Console`, `Callback`, `Queue`, `Recording`, `Server`) via handler options. The interviewer behaviour includes optional `ask_multiple/4` and `inform/4` callbacks, the console interviewer surfaces node prompt/default/timeout metadata during interactive selection, and the server interviewer exposes pending multiple-choice questions for HTTP clients. Full upstream question/answer type parity remains open. |
| `7. Validation and Linting` | `partial` | Core diagnostics exist for start/exit structure, edge source/target existence, condition parse, start reachability errors, dead-end flow warnings, retry target reference checks (including graph-level `retry_target` / `fallback_retry_target` attrs), retry count linting (`default_max_retry`, node `max_retries`), goal gate retry hints, codergen prompt warnings, unknown explicit node types, fidelity value linting, stylesheet syntax errors, plus `wait.human` choice/default checks, prompt-presence lint, ambiguous default-choice lint, timeout/default lint (`human.timeout` without `human.default_choice`), timeout-format linting, duplicate human accelerator key warnings, codergen LLM attr lint checks (`reasoning_effort`, `temperature`, `max_tokens`, provider/model pairing), `parallel` attr linting (`join_policy`, `max_parallel`, `k`, `quorum_ratio`), `stack.manager_loop` attr linting (`manager.actions`, `manager.max_cycles`, `manager.poll_interval`, autostart `stack.child_dotfile`), stylesheet lint diagnostics, `validate/2` custom lint rule hooks, and `validate_or_raise/2` error escalation. Full lint parity matrix remains open. |
| `8. Model Stylesheet` | `partial` | CSS-like `model_stylesheet` parsing is implemented (`*`, shape selectors like `box`, `.class`, `#id` with declaration blocks), including specificity ordering and same-specificity last-rule wins behavior, and is applied before validation. Backward-compatible JSON stylesheet parsing remains supported, along with extended selector support (`type=...`, `node[type=...]`, `shape=...`, `node[shape=...]`, compound selectors, selector lists, dotted handler types like `wait.human`). CSS declaration support covers codergen LLM attrs plus operational node attrs already used by the runtime (for example `timeout`, `prompt`, `command`, retry attrs, and `human.*` attrs), both `:` and `=` declaration separators, `model` -> `llm_model` aliasing, quoted values (single/double quotes), CSS comments, quoted `/* ... */` comment markers, and quoted `;`/`}` characters inside declaration values. Lint diagnostics cover unknown CSS properties, malformed declarations, invalid selectors, invalid CSS syntax, and invalid JSON-list/map rule shapes. Full strict parity remains open. |
| `9. Transforms and Extensibility` | `partial` | Extensibility exists via handlers/backends/options. A graph transform pipeline is implemented via `run/resume` options (`graph_transforms` and `graph_transform`) with function/module transform hooks applied before validation and execution, the built-in variable expansion transform resolves `$goal` placeholders in graph/node/edge string attrs before execution, and a lightweight HTTP server mode is available through `AttractorEx.start_http_server/1` with pipeline status, SSE events, cancellation, question/answer, checkpoint, context, and graph endpoints. Full graph rendering parity and broader service hardening remain open. |
| `10. Condition Expression Language` | `implemented` | Equality/inequality, numeric comparisons, clause chaining, nil/boolean handling, nested context and `outcome` access are implemented and tested. |
| `11. Definition of Done` | `partial` | Significant checklist coverage, but sections 8 and parts of 6/7/9 remain open. |
| `Appendix A/B/C/D` | `partial` | Major attrs, shape mapping, status contract, and error categories are represented; not every appendix item is fully implemented. |

## Evidence Highlights

1. DOT parsing + schema: `dot_schema_test.exs` and `parser_test.exs`.
2. Validation diagnostics: `validator_test.exs`.
3. Engine routing/retry/goal-gate: `engine_test.exs`.
4. Condition language semantics: `condition_test.exs`.
5. Built-in handlers: `handlers_test.exs`.
6. Graph transform pipeline hooks and error handling: `engine_test.exs`.
7. CSS/JSON stylesheet parsing and parser handling of quoted-string separators, quoted comment markers, CSS comments, shape selectors, `model=` aliasing, dotted handler-type selectors, operational CSS attrs, and invalid selector diagnostics: `model_stylesheet_test.exs` and `parser_test.exs`.
8. Human interviewer adapters, recording wrapper, optional multi-select/inform callbacks, console prompt metadata, and first-choice fallback for unmatched answers: `handlers_test.exs` and `interviewers_test.exs`.
9. HTTP server mode, SSE events, pending question flow, and answer submission: `http_test.exs`.

## Known Gaps vs Spec

1. Broader DOT grammar edge cases beyond the supported parsing subset.
2. Strict stylesheet parity details (for example full CSS grammar coverage and stricter rule/property enforcement beyond the current diagnostics for unknown properties, malformed declarations, invalid selectors, invalid rule shapes, and brace/syntax issues).
3. Full interviewer UX/interaction parity beyond the current named interfaces (`AutoApprove`, `Console`, `Callback`, `Queue`, `Recording`, `Server`) and optional `ask_multiple`/`inform` hooks, especially broader question/answer typing.
4. Full linting parity matrix (coverage now includes start/exit structure, reachability, edge source/target existence, graph/node retry-target reference checks, graph/node retry-count linting, explicit type/fidelity linting, `wait.human` prompt/default/timeout checks, ambiguous default-choice lint, duplicate-key checks, `parallel`/`stack.manager_loop` operational attr linting, stylesheet syntax/diagnostics, `validate_or_raise/2`, plus custom lint rule API via `Validator.validate/2`).
5. Full HTTP server mode parity details such as richer graph rendering and production-grade service concerns beyond the implemented core endpoint set.

## Verification Commands

```bash
mix test test/attractor_ex/dot_schema_test.exs
mix test test/attractor_ex/parser_test.exs test/attractor_ex/validator_test.exs
mix test test/attractor_ex/condition_test.exs test/attractor_ex/handlers_test.exs test/attractor_ex/engine_test.exs
mix test test/attractor_ex/http_test.exs
mix precommit
```
