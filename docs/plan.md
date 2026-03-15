# Implementation Plan

This planning area tracks how `attractor-phoenix` should move ahead of the reference implementations identified in `../examples/FOCUSED-RESEARCH.md`.

The plan is organized as a numbered document set so work can be tracked, revised, and expanded without turning one file into an unmaintainable backlog dump.

## Plan Index

1. [01. Mission And Competitive Benchmark](01-mission-and-competitive-benchmark.html)
2. [02. Runtime Foundation](02-runtime-foundation.html)
3. [03. Operator Surface And Debugger](03-operator-surface-and-debugger.html)
4. [04. Builder And Authoring Fidelity](04-builder-and-authoring-fidelity.html)
5. [05. Conformance And Proof](05-conformance-and-proof.html)
6. [06. Unified LLM And Agent Platform](06-unified-llm-and-agent-platform.html)
7. [07. Premium Features And Leadership Criteria](07-premium-features-and-leadership-criteria.html)

## Numbering System

The numbering scheme is intentional:

1. `01` establishes mission and benchmark criteria.
2. `02` through `06` define the major implementation workstreams.
3. `07` captures differentiators, final success criteria, risks, and execution order.

This numbering should remain stable. If more planning documents are added later, append new items rather than renumbering existing ones unless the structure becomes clearly wrong.

## Working Rules

When updating the plan:

1. Keep each numbered document focused on one workstream.
2. Reference `../examples/FOCUSED-RESEARCH.md` when a proposal is inspired by a specific repo.
3. Prefer concrete architecture and delivery decisions over vague aspirational language.
4. Keep implementation claims consistent with the tracked compliance docs and actual tests.
5. Treat this plan set as a maintained artifact rather than a one-off note.

## Suggested Next Layer

Once these plan documents are accepted, the next planning step should be to create implementation epics or issue-sized work items under the same numbering family, for example:

1. `02A` persistent run store
2. `03A` debugger MVP timeline
3. `04A` canonical parser-backed builder API
4. `05A` black-box conformance fixture harness
