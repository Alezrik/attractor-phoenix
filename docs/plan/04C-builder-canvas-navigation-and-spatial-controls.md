# 04C. Builder Canvas Navigation And Spatial Controls

Research input reviewed on 2026-03-15:

- `C:\Users\ex_ra\code\examples\FOCUSED-RESEARCH-UI.md`
- Primary references: `xyflow`, `node-red`
- Supporting reference: `n8n`

## Context

Current repo evidence:

- `assets/js/pipeline_builder.js` stores node positions as absolute coordinates and only fits nodes back into the visible box.
- `lib/attractor_phoenix_web/live/pipeline_builder_live.html.heex` renders a single canvas surface with node dragging and edge creation, but no minimap, viewport model, zoom controls, or selection tools.
- The only canvas controls today are add-edge, clear, apply DOT, and panel toggles.

The builder already supports direct manipulation, but large graphs will degrade quickly because orientation and navigation are still minimal.

## Increment Goal

Turn the current builder canvas into a navigable graph workspace with viewport state, minimap, fit-view, zoom, and multi-selection.

## Non-Goals

- Reworking authoring endpoints
- Rewriting node metadata editing
- Implementing run debugger screens

## Reference Anchors

- `xyflow`: viewport primitives, minimap, controls, non-scaling toolbars
- `node-red`: navigator pattern for large graphs
- `n8n`: selective control surfacing so the canvas stays readable

## Sprint Backlog

### UI-04C-01

- status: `done`
- title: Introduce an explicit viewport model for pan, zoom, and fit-view
- rationale: Current coordinates are canvas-relative only; there is no reusable viewport state.
- file targets:
  - `assets/js/pipeline_builder.js`
  - `lib/attractor_phoenix_web/live/pipeline_builder_live.html.heex`
  - `assets/css/app.css`
- dependencies: `04A-product-shell-and-design-system.md`
- implementation notes:
  - Add viewport state to the builder hook instead of inferring position from DOM offsets alone.
  - Support wheel zoom, drag-to-pan, fit-view, and reset-view actions.
  - Keep node drag semantics intact while distinguishing node drag from viewport drag.
- execution notes:
  - Added explicit viewport state to `PipelineBuilder` with world-space rendering through a transformed `#builder-world` layer.
  - Reworked fit-view to adjust viewport translation and zoom instead of mutating node coordinates.
  - Added wheel zoom, pan mode, reset-view, responsive grid scaling, and viewport status feedback.
- validation results:
  - `node --check assets/js/pipeline_builder.js`
  - `mix test test/attractor_phoenix_web/live/pipeline_builder_live_test.exs`
  - `mix precommit`
- verification steps:
  - Build a medium-sized graph and confirm zoom, pan, and fit-view remain stable.
  - Confirm edge rendering remains aligned after viewport transforms.
- done criteria:
  - Viewport behavior is explicit and reusable.
  - Users can reorient without manually dragging every node back into view.

### UI-04C-02

- status: `done`
- title: Add minimap and canvas control cluster
- rationale: Large-canvas orientation is currently weak and should follow the `node-red` plus `xyflow` reference shape.
- file targets:
  - `lib/attractor_phoenix_web/live/pipeline_builder_live.html.heex`
  - `assets/js/pipeline_builder.js`
  - `assets/css/app.css`
- dependencies: `UI-04C-01`
- implementation notes:
  - Add a minimap that reflects current node bounds and visible viewport.
  - Add a compact control cluster for zoom in, zoom out, fit view, and interaction mode.
  - Keep these controls visually light and collapse or fade them when not needed.
- execution notes:
  - Added a floating control cluster with zoom, fit, reset, select, pan, and connect actions.
  - Added a live minimap with node overview, selected-node highlighting, and viewport recentering via click-drag.
  - Kept controls and navigator in overlay layers so they remain readable at different zoom levels.
- validation results:
  - `mix test test/attractor_phoenix_web/live/pipeline_builder_live_test.exs`
  - `mix precommit`
- verification steps:
  - Navigate a graph using both the control cluster and the minimap.
  - Confirm minimap drag or click re-centers the viewport correctly.
- done criteria:
  - Spatial orientation no longer depends on memory alone.
  - Canvas controls are present without overwhelming the primary workspace.

### UI-04C-03

- status: `done`
- title: Add multi-select, marquee select, and contextual selection toolbar
- rationale: The current builder acts on one node at a time, which limits throughput on real workflows.
- file targets:
  - `assets/js/pipeline_builder.js`
  - `lib/attractor_phoenix_web/live/pipeline_builder_live.html.heex`
  - `assets/css/app.css`
- dependencies: `UI-04C-01`
- implementation notes:
  - Support shift-select or marquee selection for multiple nodes.
  - Add a contextual toolbar for group actions such as align, distribute, duplicate, and delete.
  - Keep toolbar scale independent from canvas zoom so controls stay readable.
- execution notes:
  - Added set-based selection state, shift-select, marquee selection, and group dragging for selected nodes.
  - Added a contextual toolbar for align row, align column, distribute horizontally, duplicate, and delete actions.
  - Updated the command palette delete action to operate on the active selection rather than only one node.
- validation results:
  - `mix test test/attractor_phoenix_web/live/pipeline_builder_live_test.exs`
  - `mix precommit`
- verification steps:
  - Select multiple nodes and apply at least one group action.
  - Confirm selection state survives moderate viewport movement and does not corrupt DOT sync.
- done criteria:
  - The builder supports basic graph-editing throughput beyond single-node editing.
  - Selection affordances stay legible at different zoom levels.

## Risks And Dependencies

- Viewport work touches edge rendering, hit testing, and drag behavior; land explicit viewport state before minimap or marquee work.
- Group actions must respect existing runtime constraints like unique start and exit nodes.

## Validation Plan

- `mix test test/attractor_phoenix_web/live/pipeline_builder_live_test.exs`
- Manual canvas stress test with medium and large graphs
