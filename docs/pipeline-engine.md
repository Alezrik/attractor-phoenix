# Pipeline Engine

## Public API

The primary entry points are:

- `AttractorEx.run/3`
- `AttractorEx.resume/3`
- `AttractorEx.validate/2`
- `AttractorEx.validate_or_raise/2`

`run/3` executes a pipeline from its start node. `resume/3` restores execution from a checkpoint map, struct, or `checkpoint.json` path.

## DOT Model

The parser converts DOT into these runtime structs:

- `AttractorEx.Graph`
- `AttractorEx.Node`
- `AttractorEx.Edge`

This model is intentionally smaller than full Graphviz DOT. It prioritizes the subset needed to execute Attractor-style workflows reliably.

## Handler Mapping

Node execution is determined by either an explicit `type` attribute or the node shape:

| Shape | Default handler type |
| --- | --- |
| `Mdiamond` | `start` |
| `Msquare` | `exit` |
| `diamond` | `conditional` |
| `component` | `parallel` |
| `tripleoctagon` | `parallel.fan_in` |
| `hexagon` | `wait.human` |
| `parallelogram` | `tool` |
| `house` | `stack.manager_loop` |
| `box` | `codergen` |

You can override this with `type="..."`, and you can register new handler modules through `AttractorEx.HandlerRegistry`.

## Routing Rules

The engine selects the next edge in this order:

1. Matching `condition=...`
2. Matching `status=...`
3. Matching the handler outcome's `preferred_label`
4. Matching the handler outcome's `suggested_next_ids`
5. Unconditional edge by weight
6. Lexical fallback

This is implemented in `AttractorEx.Engine` and matches the spec-driven behavior documented in the local compliance notes.

## Retries And Goal Gates

`AttractorEx.Engine` supports:

- Node retry policies with exponential backoff.
- Graph-level and node-level retry targets.
- Goal-gate nodes that must end in success or partial success.
- Loop restart semantics via edge metadata.

Outcomes are represented as `AttractorEx.Outcome` values and serialized through `AttractorEx.StatusContract`.

## Styling And Transforms

Before validation and execution, the engine applies:

1. Model stylesheet resolution through `AttractorEx.ModelStylesheet`
2. Variable expansion through `AttractorEx.Transforms.VariableExpansion`
3. Any custom graph transforms passed in `opts`

At runtime, codergen stages may also receive synthesized context carryover text based on fidelity settings.

## Recommended Reading

For the precise implementation details:

- `AttractorEx.Engine` for orchestration
- `AttractorEx.Validator` for lint rules
- `AttractorEx.Handlers.*` for node behavior
- `AttractorEx.StatusContract` for artifact payloads
