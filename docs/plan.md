# Implementation Plan

This planning area tracks how `attractor-phoenix` should move ahead of the reference implementations identified in `../examples/FOCUSED-RESEARCH.md`.

UI planning now also incorporates the focused graph-editor research reviewed on 2026-03-15 in `C:\Users\ex_ra\code\examples\FOCUSED-RESEARCH-UI.md`, with `n8n`, `node-red`, and `xyflow` as the primary implementation references for the Phoenix UI.

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

## UI Increment Set

These documents turn the high-level workstreams into UI-specific implementation slices sized for a developer to execute without rediscovering the entire product direction.

1. [04A. Product Shell And Design System](plan/04A-product-shell-and-design-system.md)
2. [04B. Builder Command Palette And Quick Insert](plan/04B-builder-command-palette-and-quick-insert.md)
3. [04C. Builder Canvas Navigation And Spatial Controls](plan/04C-builder-canvas-navigation-and-spatial-controls.md)
4. [04D. Builder Inspector And Runtime Sidecar](plan/04D-builder-inspector-and-runtime-sidecar.md)
5. [03A. Operator Run Topology And Live Dashboard](plan/03A-operator-run-topology-and-live-dashboard.md)
6. [03B. Debugger Timeline And Human-Gate Inbox](plan/03B-debugger-timeline-and-human-gate-inbox.md)
7. [04E. Library, Setup, And Benchmark Continuity](plan/04E-library-setup-and-benchmark-continuity.md)
