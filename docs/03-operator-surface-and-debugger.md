# 03. Operator Surface And Debugger

This workstream turns the Phoenix app from a useful demo shell into a real operations console.

Primary inspiration:

1. `attractor` for dashboard and operator-surface thinking
2. `samueljklee-attractor` for core server and event-stream behavior
3. `kilroy` for runtime state that can support richer introspection

## Goal

Ship a first-class live operator surface and debugger that materially exceeds the comparison set.

## Operator Surface Priorities

1. Subscription-driven updates instead of polling as the primary mechanism
2. Deep-linkable run views
3. Live pending-question handling
4. Searchable and filterable event histories
5. Artifact and checkpoint inspection

## Debugger Priorities

1. Event timeline with typed filtering
2. Stage-by-stage execution trace
3. Context diff between events and checkpoints
4. Retry-chain visualization
5. Edge-decision explanation
6. Human-gate inbox with answer provenance
7. Replay from checkpoint or selected stage
8. Compare two runs of the same graph

## Work Items

1. Make the dashboard subscribe to pipeline updates instead of relying on refresh loops as the default path.
2. Add dedicated run detail routes with deep linking.
3. Surface event filtering, grouping, and search.
4. Add live pending-question updates and immediate answer feedback.
5. Add live artifact refresh and checkpoint refresh without full view reloads.
6. Add a debugger LiveView with timeline, diffs, and replay controls.
7. Add run comparison and repro export workflows.

## Deliverables

1. Channel-first dashboard updates
2. Run detail page
3. Debugger LiveView
4. Context and checkpoint diff tools
5. Replay controls
6. Repro export workflow

## Success Criteria

This workstream is done when:

1. the main operator experience is live by default
2. a run can be inspected at event, stage, context, and artifact level
3. replay and comparison are operator-visible features rather than internal concepts
4. the debugger clearly feels stronger than the operator surfaces in the reference set
