# Attractor Spec Compliance (AttractorEx)

This document tracks how `AttractorEx` implementation and tests align with the upstream Attractor specification.

## Upstream Reference

- Spec URL: https://github.com/strongdm/attractor/blob/main/attractor-spec.md
- Baseline commit currently targeted by this repository: `2f892efd63ee7c11f038856b90aae57c067b77c2` (2026-02-19)

## Scope

Implementation modules:

1. `lib/attractor_ex/parser.ex`
2. `lib/attractor_ex/validator.ex`
3. `lib/attractor_ex/engine.ex`
4. `lib/attractor_ex/condition.ex`
5. `lib/attractor_ex/handlers/*.ex`

Primary verification tests:

1. `test/attractor_ex/dot_schema_test.exs`
2. `test/attractor_ex/parser_test.exs`
3. `test/attractor_ex/validator_test.exs`
4. `test/attractor_ex/handlers_test.exs`
5. `test/attractor_ex/engine_test.exs`
6. `test/attractor_ex/condition_test.exs`

## Compliance Matrix

### DOT grammar and schema parsing

Covered behavior:

1. Directed `digraph` parsing with graph defaults, node defaults, edge defaults.
2. Chained edge expansion (`a -> b -> c`) with shared edge attributes.
3. Graph-level key/value declarations (`goal="..."`) outside attribute blocks.
4. Value parsing for strings, booleans, integers, and floats.
5. Comment stripping and optional semicolons.
6. Rejection of unsupported undirected edges (`--`).
7. Canonical shape-to-node-type mapping.

Verification tests:

- `test/attractor_ex/dot_schema_test.exs`
- `test/attractor_ex/parser_test.exs`

### Validation and graph constraints

Covered behavior:

1. Required start/exit node checks.
2. Edge endpoint validity and reachability-style validation.
3. Retry and goal-gate related validation diagnostics.
4. Static graph diagnostics with severity reporting.

Verification tests:

- `test/attractor_ex/validator_test.exs`

### Runtime execution semantics

Covered behavior:

1. Start-to-exit traversal through handler outcomes.
2. Outcome status propagation through edge status/condition filters.
3. Context merge behavior and run artifact progression.
4. Retry/fallback path behavior driven by graph and node attributes.

Verification tests:

- `test/attractor_ex/engine_test.exs`

### Condition language support

Covered behavior:

1. `outcome.status == "..."` style predicates.
2. Nested context access in condition expressions.
3. Safe fallback behavior for unsupported condition forms.

Verification tests:

- `test/attractor_ex/condition_test.exs`

### Built-in handler behavior

Covered behavior:

1. `start`, `exit`, `default`, `conditional`, `parallel`, `parallel.fan_in`, `tool`, `wait.human`, `stack.manager_loop`, and `codergen` handler flows.
2. Success/failure status behavior and context updates from handlers.

Verification tests:

- `test/attractor_ex/handlers_test.exs`

## Verification Commands

Use this sequence when re-validating compliance locally:

```bash
mix test test/attractor_ex/dot_schema_test.exs
mix test test/attractor_ex/parser_test.exs test/attractor_ex/validator_test.exs
mix test test/attractor_ex/condition_test.exs test/attractor_ex/handlers_test.exs test/attractor_ex/engine_test.exs
mix precommit
```

## Maintenance Notes

1. Update this document when the upstream `attractor-spec.md` changes.
2. Add or adjust tests before changing runtime behavior.
3. Keep README references synchronized with this file and the coding-agent-loop compliance document.
