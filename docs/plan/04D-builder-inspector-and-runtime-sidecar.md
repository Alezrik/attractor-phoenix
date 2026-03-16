# 04D. Builder Inspector And Runtime Sidecar

Research input reviewed on 2026-03-15:

- `C:\Users\ex_ra\code\examples\FOCUSED-RESEARCH-UI.md`
- Primary references: `n8n`, `xyflow`

## Context

Current repo evidence:

- `lib/attractor_phoenix_web/live/pipeline_builder_live.html.heex` splits editing across a left rail, large node and edge dialogs, a dense right rail, and a result block below the builder.
- `assets/js/pipeline_builder.js` already knows which attrs are valid by node type, but the editing surface is still modal-heavy and form-dense.
- DOT, JSON context, diagnostics, library save, and run result all compete for the same right-side area.

The current builder is feature-capable, but it asks the user to manage too many disconnected editing surfaces. This increment turns those surfaces into a coherent inspector and runtime sidecar.

## Increment Goal

Unify node inspection, graph inspection, diagnostics, run controls, and run feedback into a structured sidecar experience that stays close to the canvas.

## Non-Goals

- Implementing deep debugger timelines
- Changing builder command palette behavior
- Replacing runtime endpoints

## Reference Anchors

- `n8n`: authoring-to-execution continuity and structured side panels
- `xyflow`: contextual node/edge toolbars and non-scaling side controls

## Sprint Backlog

### UI-04D-01

- status: `done`
- title: Replace large node and edge dialogs with contextual inspector modes
- rationale: Current dialogs interrupt flow and hide too much context while editing.
- file targets:
  - `lib/attractor_phoenix_web/live/pipeline_builder_live.html.heex`
  - `assets/js/pipeline_builder.js`
  - `assets/css/app.css`
- dependencies: `04A-product-shell-and-design-system.md`
- implementation notes:
  - Use a right-side inspector with mode tabs such as graph, node, edge, and selection.
  - Keep runtime-valid attr filtering from the current JS hook.
  - Reserve modal usage for destructive confirmations or advanced secondary actions.
- verification steps:
  - Edit node and edge metadata without opening a full-screen interruption.
  - Confirm all currently supported attrs remain editable.
- done criteria:
  - Node and edge editing happen in-context.
  - The inspector state tracks the current selection reliably.
- execution notes:
  - Replaced the modal node and edge editors with docked inspector panels in the builder sidecar.
  - Added inspector tab state in `assets/js/pipeline_builder.js` so selection, node, and edge editing stay synchronized with canvas interactions.
- validation results:
  - `mix compile --no-deps-check` passed after the inspector refactor.
  - `mix test --no-deps-check test/attractor_phoenix_web/live/pipeline_builder_live_test.exs` could not complete because the Erlang VM crashed on hostname resolution (`inet_gethost : einval`) after boot in this environment.

### UI-04D-02

- status: `done`
- title: Reframe diagnostics, autofix, DOT, and context as inspector tabs
- rationale: The current right rail is dense because unrelated tasks are stacked vertically.
- file targets:
  - `lib/attractor_phoenix_web/live/pipeline_builder_live.html.heex`
  - `assets/js/pipeline_builder.js`
  - `assets/css/app.css`
- dependencies: `UI-04D-01`
- implementation notes:
  - Separate DOT source, context JSON, lint diagnostics, and graph settings into explicit tabs or segmented views.
  - Preserve direct text editing, but make diagnostics the default state when errors exist.
  - Keep autofix actions close to the relevant diagnostics instead of in a detached list.
- verification steps:
  - Trigger a validation error and confirm diagnostics are the first visible state.
  - Edit DOT directly and confirm the inspector updates cleanly after canonical analysis.
- done criteria:
  - DOT and diagnostics are easier to navigate on medium screens.
  - Users can switch between source editing and graph editing without losing context.
- execution notes:
  - Split the former right rail into explicit graph, diagnostics, and source panels with tab navigation.
  - Updated diagnostics rendering so parser or validator findings pull focus to the diagnostics tab and keep autofix controls adjacent to the findings list.
- validation results:
  - `mix compile --no-deps-check` passed with the new inspector/source panel structure.
  - Focused LiveView test execution remains blocked by the environment-level `inet_gethost : einval` crash noted above.

### UI-04D-03

- status: `done`
- title: Embed run controls and recent run feedback into a runtime sidecar
- rationale: Run results currently appear as a generic block below the builder, which weakens authoring-to-execution continuity.
- file targets:
  - `lib/attractor_phoenix_web/live/pipeline_builder_live.html.heex`
  - `lib/attractor_phoenix_web/live/pipeline_builder_live.ex`
  - `assets/css/app.css`
- dependencies: `UI-04D-02`
- implementation notes:
  - Move run controls, endpoint choice, last run status, pending questions count, and recent events into a dedicated runtime pane.
  - Keep full payload dumps available, but demote them behind expandable sections.
  - Surface a clear handoff into the richer operator views from `03A` and `03B`.
- verification steps:
  - Run and submit a pipeline from the builder and confirm recent status updates appear without scrolling below the canvas.
  - Confirm builder still preserves DOT and context edits across runs.
- done criteria:
  - Builder feels connected to execution, not separate from it.
  - Important runtime feedback is visible near the canvas by default.
- execution notes:
  - Moved run controls, run status, recent events, payload details, and operator handoff links into a dedicated runtime inspector panel.
  - Demoted checkpoint, graph JSON, and payload dumps behind expandable details blocks while keeping the latest run summary visible by default.
- validation results:
  - `mix compile --no-deps-check` passed after moving runtime rendering into the sidecar.
  - Focused LiveView test execution remains blocked by the environment-level `inet_gethost : einval` crash noted above.

## Risks And Dependencies

- This increment should follow the shell/design-system work so the inspector does not invent its own component language.
- Inspector state needs careful handling around LiveView updates because the builder canvas is `phx-update="ignore"`.

## Validation Plan

- `mix test test/attractor_phoenix_web/live/pipeline_builder_live_test.exs`
- Manual builder run/submit smoke test
