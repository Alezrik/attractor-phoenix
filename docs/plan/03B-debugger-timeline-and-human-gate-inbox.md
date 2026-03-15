# 03B. Debugger Timeline And Human-Gate Inbox

Research input reviewed on 2026-03-15:

- `C:\Users\ex_ra\code\examples\FOCUSED-RESEARCH-UI.md`
- Primary reference: `n8n`
- Supporting references: `node-red`, `xyflow`

## Context

Current repo evidence:

- `lib/attractor_phoenix_web/live/dashboard_live.html.heex` shows recent events, checkpoint payloads, graph payloads, and question forms, but only as stacked JSON/text panels.
- `lib/attractor_phoenix_web/live/dashboard_live.ex` already fetches status, context, checkpoint, questions, events, and multiple graph formats for a selected run.
- There is no dedicated event timeline, event filtering, diff view, or focused human-gate inbox.

This increment converts the raw operator payloads already present in the repo into a debugger surface that supports diagnosis instead of only inspection.

## Increment Goal

Build a dedicated debugger experience with event timeline, question handling, checkpoint/context inspection, and clear cross-links back to the run overview.

## Non-Goals

- Adding replay endpoints that do not yet exist
- Redesigning the builder canvas
- Replacing existing run submission flows

## Reference Anchors

- `n8n`: execution detail continuity, retry/debug framing, operator-grade run analysis
- `node-red`: dense event/problem visibility for power users
- `xyflow`: small contextual controls around selected items and panes

## Sprint Backlog

### UI-03B-01

- status: `done`
- title: Add a dedicated debugger layout with timeline-first hierarchy
- rationale: The current payload blocks bury event flow and make the operator infer order from raw JSON.
- file targets:
  - `lib/attractor_phoenix_web/router.ex`
  - `lib/attractor_phoenix_web/live/run_live.ex`
  - `lib/attractor_phoenix_web/live/run_live.html.heex`
  - `lib/attractor_phoenix_web/live/debugger_live.ex`
  - `lib/attractor_phoenix_web/live/debugger_live.html.heex`
  - `assets/css/app.css`
- dependencies: `03A-operator-run-topology-and-live-dashboard.md`
- implementation notes:
  - Add a debugger route or debugger mode nested under the new run detail topology.
  - Make the event timeline the primary pane and move raw payloads into expandable detail views.
  - Use typed event chips, state markers, and clear stage ordering.
- execution notes:
  - Added `DebuggerLive` at `/runs/:id/debugger` and linked it from the run overview.
  - Promoted the chronological timeline into the primary debugger pane and moved payload inspection into the event inspector.
  - Reused `OperatorRunData` to normalize event titles, summaries, metadata, and selection state across the operator surface.
- verification steps:
  - Open a run debugger from the run detail route.
  - Confirm events are readable in chronological order without raw JSON as the primary representation.
- validation results:
  - `mix test test/attractor_phoenix_web/live/dashboard_live_test.exs` passed on 2026-03-15.
- done criteria:
  - The debugger has its own route and layout.
  - Timeline is the first-class surface, not an afterthought.

### UI-03B-02

- status: `done`
- title: Add event filtering, search, and focused event detail drawers
- rationale: Operators need to isolate failures, retries, question events, and specific nodes quickly.
- file targets:
  - `lib/attractor_phoenix_web/live/debugger_live.ex`
  - `lib/attractor_phoenix_web/live/debugger_live.html.heex`
  - `assets/css/app.css`
- dependencies: `UI-03B-01`
- implementation notes:
  - Support filters by event type, status, node id, and free-text query when payloads make that possible.
  - Add a side drawer or inspector for the currently selected event.
  - Keep filter state encoded in the URL when practical so debugger views are shareable.
- execution notes:
  - Added URL-backed filters for focus, event type, status, node, and free-text search.
  - Timeline selection now patches the URL with the selected event sequence.
  - Added a dedicated inspector panel with structured metadata plus expandable payload and status-alias views.
- verification steps:
  - Filter to failures only, then to question events only, and inspect event detail.
  - Confirm URL state survives refresh when filters are encoded there.
- validation results:
  - Added LiveView coverage for debugger query state and filter patching in `test/attractor_phoenix_web/live/dashboard_live_test.exs`.
- done criteria:
  - Operators can isolate important events without scanning the full history.
  - Event details are structured and do not require reading the entire payload dump.

### UI-03B-03

- status: `done`
- title: Add checkpoint/context diff panels and a dedicated human-gate inbox
- rationale: The repo already fetches checkpoint, context, and questions, but the current presentation does not explain what changed or what action is needed.
- file targets:
  - `lib/attractor_phoenix_web/live/debugger_live.ex`
  - `lib/attractor_phoenix_web/live/debugger_live.html.heex`
  - `assets/css/app.css`
  - `test/attractor_phoenix_web/live/dashboard_live_test.exs`
- dependencies: `UI-03B-01`
- implementation notes:
  - Compare adjacent checkpoints or event-adjacent context snapshots where data is available.
  - Move question answering into a dedicated inbox pane with provenance, timeout, and default-choice emphasis.
  - Provide explicit links back to the run overview and builder when operator action escalates.
- execution notes:
  - Added checkpoint-vs-current-context diff summaries and highlighted added, changed, and removed keys.
  - Moved question handling into a dedicated debugger inbox with provenance, timeout badges, option routing notes, and default emphasis.
  - Added explicit navigation back to the run overview and builder from the debugger header.
- verification steps:
  - Answer a question from the debugger and confirm immediate visual feedback.
  - Inspect a checkpoint/context comparison and confirm changed sections are highlighted.
- validation results:
  - `mix test test/attractor_phoenix_web/live/dashboard_live_test.exs` passed with debugger inbox answer coverage on 2026-03-15.
  - `mix precommit` remains blocked by existing failures in `test/attractor_ex/interviewer_server_test.exs` (`Manager.submit_answer/4` returning `{:error, :not_found}` for `server-yes-no` and `server-list`), which are outside the debugger UI files touched here.
- done criteria:
  - Human-gate work is visually separated from passive inspection.
  - Debugger helps operators identify state changes instead of only showing full payloads.

## Risks And Dependencies

- Rich diffing may require retaining prior snapshots client-side if the API does not expose historical diffs directly.
- If replay controls are not yet feasible, keep the UI honest and mark them as deferred rather than shipping dead controls.

## Validation Plan

- `mix test test/attractor_phoenix_web/live/dashboard_live_test.exs`
- Manual run-debugger smoke test using a pipeline with events and at least one question
