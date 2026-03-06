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
3. Baseline commit currently implemented/tested against:
   `2f892efd63ee7c11f038856b90aae57c067b77c2` (2026-02-19)

## Keeping Up with Upstream

1. Refresh local reference clone: `git -C ..\\_attractor_reference fetch --all --prune`
2. Compare baseline: `git -C ..\\_attractor_reference rev-parse HEAD`
3. If changed, review spec diff and update `AttractorEx` tests first, then implementation.
