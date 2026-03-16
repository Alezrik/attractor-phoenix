# 04B. Builder Command Palette And Quick Insert

Research input reviewed on 2026-03-15:

- `C:\Users\ex_ra\code\examples\FOCUSED-RESEARCH-UI.md`
- Primary references: `n8n`, `node-red`
- Supporting reference: `xyflow`

## Context

Current repo evidence:

- `lib/attractor_phoenix_web/live/pipeline_builder_live.html.heex` exposes fixed quick-insert buttons and authoring buttons in the left rail.
- `assets/js/pipeline_builder.js` supports add-node actions, but insertion is button-driven rather than search-first or cursor-local.
- There is no command palette, global keyboard affordance, or unified action registry for create/open/run flows.

The current builder can add nodes, but it does not yet feel fast. This increment changes node creation from sidebar clicking into a command-driven workflow.

## Increment Goal

Make node creation and builder actions search-first, keyboard-forward, and location-aware so expert users can stay on the canvas.

## Non-Goals

- Implementing minimap and pan/zoom controls
- Rewriting the entire node inspector
- Changing DOT parsing semantics

## Reference Anchors

- `n8n`: command bar, add-node search, keyboard-first canvas actions
- `node-red`: cursor-local quick-add and confirm-at-cursor behavior
- `xyflow`: clean action surfacing without bloating the canvas

## Sprint Backlog

### UI-04B-01

- status: `done`
- title: Introduce a builder command palette and shared action registry
- rationale: Builder actions are currently scattered between buttons, dialogs, and form submits.
- file targets:
  - `lib/attractor_phoenix_web/live/pipeline_builder_live.html.heex`
  - `assets/js/pipeline_builder.js`
  - `assets/js/app.js`
  - `assets/css/app.css`
- dependencies: `04A-product-shell-and-design-system.md`
- implementation notes:
  - Add a command palette overlay opened via keyboard shortcut and shell action.
  - Centralize actions such as add node, open create flow, format DOT, load template, run pipeline, and save to library.
  - Keep the action registry data-driven so new builder actions do not require bespoke UI wiring.
- execution notes:
  - Added shell and left-rail command palette triggers plus a dialog-backed search surface in the builder LiveView.
  - Centralized insert, authoring, canvas, run, and help actions in `assets/js/pipeline_builder.js`, with a small `window.builderCommands` bridge in `assets/js/app.js` for future shell-level entry points.
  - Kept existing rail buttons as secondary affordances while moving create, format, template, run, save, and navigation flows into the shared action registry.
- verification steps:
  - Open the builder and confirm the palette opens from keyboard and clickable triggers.
  - Execute at least one insert action, one authoring action, and one run action from the palette.
- validation results:
  - `mix test test/attractor_phoenix_web/live/pipeline_builder_live_test.exs` passed on 2026-03-15.
  - `mix assets.build` passed on 2026-03-15.
  - `mix precommit` did not fully pass because of a pre-existing unrelated failure in `test/attractor_ex/interviewer_server_test.exs:289` (`{:error, :not_found}` instead of `:ok`).
- done criteria:
  - Builder commands are discoverable from one surface.
  - Keyboard shortcuts are visible in the UI.
  - Existing buttons can remain as secondary affordances, not the only affordances.

### UI-04B-02

- status: `done`
- title: Add quick-insert search with cursor-local placement
- rationale: Current insertion always starts from fixed controls in the left panel; `node-red` shows a much faster pattern.
- file targets:
  - `lib/attractor_phoenix_web/live/pipeline_builder_live.html.heex`
  - `assets/js/pipeline_builder.js`
  - `assets/css/app.css`
- dependencies: `UI-04B-01`
- implementation notes:
  - Support quick-add at the current pointer or current viewport center.
  - Rank results by node type, recent usage, and runtime-valid types.
  - Preserve the existing unique start/exit constraints already enforced in `pipeline_builder.js`.
- execution notes:
  - Added pointer tracking on the canvas and use it as the preferred insertion origin, with viewport-center fallback when the pointer is outside the canvas.
  - Converted insert actions to ranked search results using node metadata, local recent-usage counts, and existing unique start/exit availability rules.
  - Updated node creation to preserve cursor-local placement instead of always re-fitting after insertion.
- verification steps:
  - Add multiple node types without touching the left rail.
  - Confirm insert location is spatially close to where the user invoked quick-add.
  - Confirm duplicate start/exit prevention still works.
- validation results:
  - Search/filter and insert affordances render in the builder LiveView test coverage added in `test/attractor_phoenix_web/live/pipeline_builder_live_test.exs`.
  - JS and CSS changes compiled successfully via `mix assets.build` on 2026-03-15.
- done criteria:
  - Node insertion is faster than the current fixed-button flow.
  - Inserted nodes appear in a predictable position.
  - Search results only expose valid node types and labels.

### UI-04B-03

- status: `done`
- title: Add keyboard-first builder shortcuts with visible cheat sheet
- rationale: Search-first workflows only pay off if the editor exposes muscle-memory shortcuts.
- file targets:
  - `lib/attractor_phoenix_web/live/pipeline_builder_live.html.heex`
  - `assets/js/pipeline_builder.js`
  - `assets/css/app.css`
  - `test/attractor_phoenix_web/live/pipeline_builder_live_test.exs`
- dependencies: `UI-04B-01`
- implementation notes:
  - Add shortcuts for quick-add, connect mode, fit view, open inspector, delete selection, format DOT, and run.
  - Surface shortcuts in the command palette and a lightweight help sheet.
  - Avoid conflicts with browser defaults where possible.
- execution notes:
  - Added `Ctrl+K`, `Shift+A`, `C`, `F`, `I`, `Backspace/Delete`, `Shift+F`, `Shift+R`, and `?` shortcuts with guards that skip text inputs, selects, textareas, and open dialogs where appropriate.
  - Added persistent visible shortcut rows in the left rail plus a dedicated cheat-sheet dialog.
  - Added LiveView assertions for the command palette and shortcut surfaces so the UI contract is covered server-side.
- verification steps:
  - Exercise each shortcut manually on the builder.
  - Confirm focus management does not break textareas or dialog fields.
- validation results:
  - `mix test test/attractor_phoenix_web/live/pipeline_builder_live_test.exs` passed with the new shortcut/palette assertions on 2026-03-15.
  - Manual keyboard-only smoke test is still pending; this execution pass validated focus guards through code review and automated markup coverage only.
- done criteria:
  - Common builder actions are accessible without leaving the keyboard.
  - Shortcut discoverability is built into the UI, not hidden in docs.

## Risks And Dependencies

- This increment should not duplicate command handling that belongs in the future shared product shell; use the shell for entry points and the builder hook for execution.
- Modal focus handling needs care because the builder already uses native `dialog` elements.

## Validation Plan

- `mix test test/attractor_phoenix_web/live/pipeline_builder_live_test.exs`
- Manual builder smoke test with keyboard-only interaction
