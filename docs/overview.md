# AttractorEx Overview

`AttractorEx` is the standalone pipeline engine embedded in this Phoenix project. It implements a practical, execution-oriented subset of the [strongDM Attractor specification](https://github.com/strongdm/attractor/blob/main/attractor-spec.md) and extends it with an HTTP control plane, human-in-the-loop adapters, a unified LLM client layer, and a coding-agent session model.

## What It Does

At a high level, `AttractorEx` turns DOT graphs into executable workflows:

1. Parse a DOT graph into a normalized runtime model.
2. Validate structural, routing, and handler-specific constraints.
3. Execute nodes from `start` to `exit`.
4. Route across edges by condition, status, preferred labels, or suggested next IDs.
5. Persist status artifacts, checkpoints, and per-stage outputs.

## Architecture

The library is organized into a small set of focused layers:

| Layer | Main modules | Responsibility |
| --- | --- | --- |
| Entry points | `AttractorEx`, `AttractorEx.Engine` | Public API and execution orchestration |
| DOT model | `AttractorEx.Parser`, `AttractorEx.Graph`, `AttractorEx.Node`, `AttractorEx.Edge` | Parse and normalize the graph |
| Validation | `AttractorEx.Validator`, `AttractorEx.Condition`, `AttractorEx.ModelStylesheet` | Linting, schema checks, and selector-based styling |
| Runtime handlers | `AttractorEx.HandlerRegistry`, `AttractorEx.Handlers.*` | Node execution semantics |
| Human gates | `AttractorEx.HumanGate`, `AttractorEx.Interviewer`, `AttractorEx.Interviewers.*` | `wait.human` workflows and answer normalization |
| HTTP service | `AttractorEx.HTTP`, `AttractorEx.HTTP.Manager`, `AttractorEx.HTTP.Router` | Remote pipeline execution and SSE updates |
| Unified LLM | `AttractorEx.LLM.*` | Provider-agnostic completion and streaming |
| Agent loop | `AttractorEx.Agent.*` | Spec-inspired coding-agent session primitives |

## Core Execution Flow

`AttractorEx.run/3` follows the same broad lifecycle documented in the upstream spec:

1. Parse DOT input.
2. Apply built-in and custom graph transforms.
3. Validate the transformed graph.
4. Create a run directory and manifest.
5. Execute node handlers one step at a time.
6. Write `status.json` and `checkpoint.json` artifacts.
7. Emit structured events for observers and the HTTP service.

## Output Artifacts

Each run writes runtime artifacts under the configured logs root:

- `manifest.json` for run metadata.
- `checkpoint.json` for resumable state.
- `status.json` for per-stage and final outcome serialization.
- Handler-specific files such as `prompt.md`, `response.md`, and tool hook logs.

## Reading The Docs

The rest of this documentation is structured to match how the code is used:

- [Pipeline Engine](pipeline-engine.html) for graph execution semantics.
- [Human-in-the-Loop](human-in-the-loop.html) for `wait.human` flows.
- [HTTP API](http-api.html) for service mode and transport contracts.
- [Agent Loop](agent-loop.html) for coding-agent session primitives.
- [Spec Alignment](spec-alignment.html) for implementation status against the upstream documents.

For source-level details, browse the grouped module documentation in the sidebar.
