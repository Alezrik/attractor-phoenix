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
| `2. DOT DSL Schema` | `partial` | Supports directed graphs, attrs, chained edges, defaults, class attr, shape mapping, comments, value parsing, and recursive inline/nested `subgraph` flattening. Full grammar coverage is not fully implemented. |
| `3. Pipeline Execution Engine` | `implemented` | Start-to-exit loop, edge selection priority, goal gates, retries/backoff, failure routing, loop restart, checkpoint/manifest/status artifacts are implemented. |
| `4. Node Handlers` | `implemented` | Built-ins present: `start`, `exit`, `codergen`, `wait.human`, `conditional`, `parallel`, `parallel.fan_in`, `tool`, `stack.manager_loop`, default fallback. |
| `5. State and Context` | `implemented` | Context merge and per-node artifacts/checkpoints implemented. First-class resume API is available via `AttractorEx.resume/3` using a checkpoint struct/map or `checkpoint.json` path. |
| `6. Human-in-the-Loop` | `partial` | `wait.human` supports context-driven answers, timeout/default handling, and interviewer abstractions (`AutoApprove`, `Console`, `Callback`, `Queue`) via handler options. Full upstream interviewer UX parity remains open. |
| `7. Validation and Linting` | `partial` | Core diagnostics exist (start/exit, edges, condition parse, unreachable/dead-end flow warnings, retry target reference checks, goal gate retry hints, codergen prompt warning) plus `wait.human` choice/default checks and `validate/2` custom lint rule hooks. Full lint parity matrix remains open. |
| `8. Model Stylesheet` | `partial` | JSON `model_stylesheet` parsing is implemented with selector application for `node`/`*`, `type=...` and `node[type=...]` (quoted/unquoted), `.class`/`node.class` (including multi-class), `#id`/`node#id`, compound selectors (for example `node[type=codergen].critical#review`), and comma-separated selector lists. Specificity now follows id > class > type > global. Full upstream selector/precedence parity is still open. |
| `9. Transforms and Extensibility` | `partial` | Extensibility exists via handlers/backends/options. A graph transform pipeline is implemented via `run/resume` options (`graph_transforms` and `graph_transform`) with function/module transform hooks applied before validation and execution. HTTP server mode is not implemented. |
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

## Known Gaps vs Spec

1. Broader DOT grammar edge cases beyond the supported parsing subset.
2. Full model stylesheet selector/precedence parity beyond the implemented node selector subset (compound id/class/type/global selectors and selector lists).
3. Full interviewer UX/interaction parity beyond the current named interfaces (`AutoApprove`, `Console`, `Callback`, `Queue`).
4. Full linting parity matrix (coverage now includes flow reachability and retry-target reference checks plus custom lint rule API via `Validator.validate/2`).
5. HTTP server mode.

## Verification Commands

```bash
mix test test/attractor_ex/dot_schema_test.exs
mix test test/attractor_ex/parser_test.exs test/attractor_ex/validator_test.exs
mix test test/attractor_ex/condition_test.exs test/attractor_ex/handlers_test.exs test/attractor_ex/engine_test.exs
mix precommit
```
