# Attractor Spec Compliance (AttractorEx)

This document tracks current compliance against the upstream Attractor specification and is written to render cleanly in ExDoc.

## Source Documents

- Attractor spec: https://github.com/strongdm/attractor/blob/main/attractor-spec.md
- Repository: https://github.com/strongdm/attractor
- Upstream HEAD reviewed: `2f892efd63ee7c11f038856b90aae57c067b77c2` (checked 2026-03-06)

## Scope

### Primary Implementation

1. `lib/attractor_ex/parser.ex`
2. `lib/attractor_ex/validator.ex`
3. `lib/attractor_ex/engine.ex`
4. `lib/attractor_ex/condition.ex`
5. `lib/attractor_ex/handlers/*.ex`

### Primary Tests

1. `test/attractor_ex/dot_schema_test.exs`
2. `test/attractor_ex/parser_test.exs`
3. `test/attractor_ex/validator_test.exs`
4. `test/attractor_ex/condition_test.exs`
5. `test/attractor_ex/handlers_test.exs`
6. `test/attractor_ex/engine_test.exs`

## Status Summary

Legend: `implemented`, `partial`, `not implemented`.

| Upstream section | Status |
| --- | --- |
| `2. DOT DSL Schema` | `partial` |
| `3. Pipeline Execution Engine` | `implemented` |
| `4. Node Handlers` | `implemented` |
| `5. State and Context` | `implemented` |
| `6. Human-in-the-Loop` | `implemented` |
| `7. Validation and Linting` | `implemented` |
| `8. Model Stylesheet` | `implemented` |
| `9. Transforms and Extensibility` | `implemented` |
| `10. Condition Expression Language` | `implemented` |
| `11. Definition of Done` | `implemented` |
| `Appendix A/B/C/D` | `partial` |

## Section Details

### `2. DOT DSL Schema` — `partial`

Implemented:

- Directed graphs, chained edges, and order-sensitive node and edge defaults
- `strict digraph`
- Compact attr statements such as `graph[...]`, `node[...]`, and `edge[...]`
- Multi-line, repeated, comma-separated, and semicolon-separated attr blocks
- Class attrs and shape mapping
- Bare, quoted, and HTML-like graph and node identifiers
- Bare graph IDs with hyphens and numeric node IDs
- Single-quoted and double-quoted attr values
- Escaped newline, tab, and carriage-return handling in quoted strings
- Quote-aware statement splitting and comment stripping
- Node-port edge endpoint parsing such as `a:out -> b:in:nw`
- Recursive inline and nested `subgraph` flattening
- Scoped default inheritance and subgraph-label-derived classes
- Subgraphs used directly as edge endpoints

Not yet complete:

- Full Graphviz grammar parity

### `3. Pipeline Execution Engine` — `implemented`

Implemented:

- Start-to-exit execution loop
- Edge selection priority
- Goal gates
- Retries and backoff
- Failure routing
- Loop restart handling
- Checkpoint, manifest, and status artifacts
- Spec default `default_max_retry=50` behavior

### `4. Node Handlers` — `implemented`

Built-in handlers present:

- `start`
- `exit`
- `codergen`
- `wait.human`
- `conditional`
- `parallel`
- `parallel.fan_in`
- `tool`
- `stack.manager_loop`
- default fallback

### `5. State and Context` — `implemented`

Implemented:

- Context merge behavior
- `graph.*` context mirroring
- `current_node` tracking
- Per-node artifacts and checkpoints
- First-class resume API via `AttractorEx.resume/3`
- Resume from checkpoint struct, map, or `checkpoint.json`

### `6. Human-in-the-Loop` — `implemented`

Implemented:

- Context-driven answers
- Timeout and default handling
- Blank-answer default routing
- Unmatched-answer fallback to the first outgoing choice
- Skip handling
- Single-select and multi-select routing via `human.multiple`
- Structured answer normalization
- Interviewer abstractions: `AutoApprove`, `Console`, `Callback`, `Queue`, `Recording`, `Server`
- Optional `ask_multiple/4` and `inform/4` interviewer callbacks
- Shared normalized question contract:
  - `FREEFORM`
  - `CONFIRMATION`
  - `YES_NO`
  - `MULTIPLE_CHOICE`
- Rich structured answer extraction:
  - `answer`
  - `value`
  - `selected`
  - `answers`
  - `keys`
- Console prompt/default/timeout/input-mode metadata
- JSON-structured console input
- Recording interviewer answer payload capture
- Server interviewer pending-question exposure
- Server-side choice metadata:
  - `multiple`
  - `required`
  - input mode
  - choice count
- `human.required` and `human.input` metadata overrides
- Immediate pending-question registration before `InterviewStarted`
- Answer payload metadata on completion events
- Day-based timeout suffix parsing such as `1d`

### `7. Validation and Linting` — `implemented`

Implemented:

- `Validator.validate/2`
- `Validator.validate_or_raise/2`
- Start and exit structure checks
- Edge source and target existence checks
- Condition parse errors
- Reachability errors and dead-end flow warnings
- Retry-target reference checks
- Graph-level `retry_target` and `fallback_retry_target`
- Spec-aligned `retry_target_exists` lint metadata
- Graph-level retry-path reachability
- Retry-count linting for `default_max_retry` and node `max_retries`
- Goal-gate retry hints without false positives when graph-level retry targets exist
- Prompt-or-label warnings for nodes that resolve to the codergen handler
- Unknown explicit node types
- Fidelity value linting
- Stylesheet syntax errors
- `wait.human` choice and default checks
- Prompt-presence lint
- Ambiguous default-choice lint
- `human.multiple`, `human.required`, and `human.input` attr linting
- Timeout/default lint when `human.timeout` lacks `human.default_choice`
- Timeout-format linting
- Duplicate human accelerator key warnings
- Codergen LLM attr linting:
  - `reasoning_effort`
  - `temperature`
  - `max_tokens`
  - provider/model pairing
- `parallel` attr linting:
  - `join_policy`
  - `max_parallel`
  - `k`
  - `quorum_ratio`
- `stack.manager_loop` attr linting:
  - `manager.actions`
  - `manager.max_cycles`
  - `manager.poll_interval`
  - `stack.child_autostart`
  - autostart `stack.child_dotfile`
- `allow_partial` boolean linting
- Stylesheet lint diagnostics
- Spec-aligned `rule` metadata on diagnostics
- Custom lint rule hooks through `validate/2`
- Error escalation through `validate_or_raise/2`

Coverage basis:

- Primary: `validator_test.exs`
- Public API wrappers: `attractor_ex_test.exs`

### `8. Model Stylesheet` — `implemented`

Implemented:

- CSS-like `model_stylesheet` parsing
- Selectors:
  - `*`
  - shape selectors such as `box`
  - `.class`
  - `#id`
  - `type=...`
  - `node[type=...]`
  - `shape=...`
  - `node[shape=...]`
  - compound selectors
  - selector lists
  - dotted handler types such as `wait.human`
  - single-quoted selector values such as `node[type='wait.human']`
- Specificity ordering and same-specificity last-rule wins behavior
- Pre-validation application while preserving explicit node attrs as the final override
- Backward-compatible JSON stylesheet parsing
- CSS declaration support for:
  - codergen LLM attrs
  - operational attrs such as `timeout`, `prompt`, `command`, and retry attrs
  - `human.*` attrs including `human.multiple`, `human.required`, and `human.input`
- Both `:` and `=` declaration separators
- `model` -> `llm_model` aliasing
- Quoted values with escapes
- CSS comments
- Quoted `/* ... */` comment markers
- Quoted `;` and `}` characters inside declaration values
- Invalid selectors ignored during parse so lint can report them non-fatally

Lint diagnostics cover:

- Unknown CSS properties
- Malformed declarations
- Invalid selectors
- Invalid CSS syntax
- Invalid JSON list or map rule shapes

### `9. Transforms and Extensibility` — `implemented`

Implemented:

- Extensibility via handlers, backends, and runtime options
- Graph transform pipeline through:
  - `graph_transforms`
  - legacy `graph_transform`
- Function hooks plus module transforms supporting:
  - spec-style `apply/1`
  - backward-compatible `transform/1`
- Built-in transforms:
  - stylesheet application
  - `$goal` variable expansion
  - runtime preamble synthesis for non-`full` codergen stages
- Optional HTTP server mode through `AttractorEx.start_http_server/1`
- Section-9 core HTTP endpoint set:
  - pipeline status
  - SSE events
  - cancellation
  - question and answer
  - checkpoint
  - context
  - graph responses in SVG, DOT, JSON, Mermaid, and plain text
- Definition-of-done compatibility aliases:
  - `POST /run`
  - `GET /status`
  - `POST /answer`
- HTTP hardening:
  - empty pipeline submissions rejected
  - unsupported graph formats rejected with explicit `400`
  - oversized request bodies rejected with explicit `413`
  - `no-store` and `nosniff` response headers
  - 1 MB JSON body limit by default

### `10. Condition Expression Language` — `implemented`

Implemented and tested:

- Equality and inequality
- Numeric comparisons
- Clause chaining
- Nil and boolean handling
- Nested context and `outcome` access

### `11. Definition of Done` — `implemented`

Implemented:

- Definition-of-done coverage across parser, validator, engine, handlers, interviewer flows, stylesheet support, transforms, and HTTP tests
- Section `11.11` HTTP compatibility aliases:
  - `POST /run`
  - `GET /status`
  - `POST /answer`

### `Appendix A/B/C/D` — `partial`

Represented today:

- Major attrs
- Shape mapping
- Status contract
- Error categories
- Graph-level `tool_hooks.pre` and `tool_hooks.post`
- `stack.child_workdir`
- Appendix C `status.json` fields:
  - `outcome`
  - `preferred_next_label`
  - `suggested_next_ids`
  - `context_updates`
  - `notes`
- Backward-compatible status aliases
- Appendix D-style runtime error categorization surfaced on outcomes, terminal results, and failure events

Not yet complete:

- Full appendix coverage

## Evidence Highlights

1. DOT parsing and schema: `dot_schema_test.exs` and `parser_test.exs`
   Evidence includes `strict digraph`, compact attr statements, quoted and HTML-like graph/node identifiers, bare graph IDs with hyphens, numeric node IDs, repeated attr blocks, line-, comma-, and semicolon-separated attr declarations, escaped newline and tab handling, node-port endpoint parsing, and subgraph edge endpoint expansion.
2. Validation diagnostics: `validator_test.exs` plus public wrapper coverage in `attractor_ex_test.exs`
   Evidence includes start/exit structure, reachability including graph-level retry paths, condition syntax metadata, retry-target and retry-count linting, goal-gate retry hints, `wait.human` prompt/default/timeout checks, codergen/parallel/manager attr linting, stylesheet diagnostics, custom rules, diagnostic `rule` metadata, and `validate_or_raise/2`.
3. Engine routing, retries, and goal gates: `engine_test.exs`
4. Condition language semantics: `condition_test.exs`
5. Built-in handlers: `handlers_test.exs`
6. Graph transform pipeline, spec-style `apply/1` compatibility, built-in variable expansion, runtime preamble synthesis, and transform error handling: `engine_test.exs`
7. CSS and JSON stylesheet parsing plus parser handling of quoted separators, escaped strings, quoted comment markers, CSS comments, shape selectors, `model=` aliasing, single-quoted selector values, dotted handler-type selectors, operational CSS attrs, and invalid selector diagnostics: `model_stylesheet_test.exs` and `parser_test.exs`
8. Human interviewer adapters, recording wrapper, optional multi-select/inform callbacks, end-to-end `wait.human` multi-select routing, console prompt metadata, first-choice fallback, and server-side question inference and metadata: `handlers_test.exs`, `interviewers_test.exs`, and `interviewer_server_test.exs`
9. HTTP server mode, SSE events, pending question flow, answer submission, SVG/DOT/JSON/Mermaid/plain-text graph variants, compatibility aliases, invalid-request handling, and pending-question metadata exposure: `http_test.exs`

## Known Gaps vs Spec

1. Full Graphviz DOT grammar parity remains incomplete beyond the supported runtime-oriented subset.
2. Examples of missing DOT parity include richer HTML-string fidelity, richer endpoint forms, and unsupported `attr_stmt` variations that do not map cleanly to AttractorEx execution semantics.

## Verification Commands

```bash
mix test test/attractor_ex/dot_schema_test.exs
mix test test/attractor_ex/parser_test.exs test/attractor_ex/validator_test.exs
mix test test/attractor_ex/condition_test.exs test/attractor_ex/handlers_test.exs test/attractor_ex/engine_test.exs
mix test test/attractor_ex/interviewer_server_test.exs
mix test test/attractor_ex/http_test.exs
mix docs
mix precommit
```
