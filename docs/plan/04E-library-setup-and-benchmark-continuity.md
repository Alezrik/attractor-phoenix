# 04E. Library, Setup, And Benchmark Continuity

Research input reviewed on 2026-03-15:

- `C:\Users\ex_ra\code\examples\FOCUSED-RESEARCH-UI.md`
- Primary reference: `n8n`

## Context

Current repo evidence:

- `lib/attractor_phoenix_web/live/pipeline_library_live.html.heex`, `setup_live.html.heex`, and `benchmark_live.html.heex` each have custom visual structure, but they do not yet feel like deliberate extensions of the same workflow product.
- Supporting routes still rely on repeated card, badge, and panel patterns that should be inherited from the design system.
- The strongest product continuity today exists between builder and library deep links, but even that handoff is mostly informational.

These routes are important because they teach the product. If they remain visually and structurally separate, the app will still feel like several demos rather than one world-class UI.

## Increment Goal

Bring the supporting routes into the same product language as the builder and operator surfaces, with clearer action hierarchy and better route-to-route continuity.

## Non-Goals

- Rewriting LLM setup behavior
- Replacing benchmark content or business logic
- Introducing database-backed library storage

## Reference Anchors

- `n8n`: consistent product shell across setup, history, and workflow authoring surfaces

## Sprint Backlog

### UI-04E-01

- status: `todo`
- title: Rework library as a launchpad instead of a CRUD list
- rationale: The current library route is usable, but it behaves more like an admin page than a workflow launch surface.
- file targets:
  - `lib/attractor_phoenix_web/live/pipeline_library_live.ex`
  - `lib/attractor_phoenix_web/live/pipeline_library_live.html.heex`
  - `assets/css/app.css`
- dependencies: `04A-product-shell-and-design-system.md`
- implementation notes:
  - Emphasize preview, last-updated state, and one-click jump into builder.
  - Separate create/edit form density from browse/load density.
  - Add visual cues for templates, recently used entries, and editable drafts if the current data supports it.
- verification steps:
  - Browse the library, load an entry into builder, and return back without losing route clarity.
  - Confirm create/edit flows still work.
- done criteria:
  - The library reads as a builder accelerator, not just storage.
  - The main call to action is loading or continuing work.

### UI-04E-02

- status: `todo`
- title: Make setup feel like a provider control room with clearer health states
- rationale: Setup already surfaces useful information, but state changes and provider health are not visually prioritized enough.
- file targets:
  - `lib/attractor_phoenix_web/live/setup_live.ex`
  - `lib/attractor_phoenix_web/live/setup_live.html.heex`
  - `assets/css/app.css`
- dependencies: `04A-product-shell-and-design-system.md`
- implementation notes:
  - Reframe provider cards around status, recency, mode, and default-role clarity.
  - Improve hierarchy between credential entry, fetch settings, and default model selection.
  - Keep sensitive values protected while making status easier to scan.
- verification steps:
  - Save keys, fetch settings, and update the default model while reviewing the route at mobile and desktop sizes.
  - Confirm error states remain visible and actionable.
- done criteria:
  - Provider health is immediately scannable.
  - The route communicates setup state before exposing raw form density.

### UI-04E-03

- status: `todo`
- title: Tighten benchmark page hierarchy and connect it to execution routes
- rationale: The benchmark page has strong content, but its current layout is long and uniformly weighted.
- file targets:
  - `lib/attractor_phoenix_web/live/benchmark_live.ex`
  - `lib/attractor_phoenix_web/live/benchmark_live.html.heex`
  - `assets/css/app.css`
- dependencies: `04A-product-shell-and-design-system.md`
- implementation notes:
  - Re-rank sections so current score, blocked criteria, immediate next steps, and execution order are easier to reach.
  - Use denser panels and clearer action links into builder, dashboard, and relevant docs.
  - Keep long-form evidence available, but reduce first-screen overload.
- verification steps:
  - Review benchmark page from top to bottom and confirm the primary narrative is visible without excessive scrolling.
  - Confirm links into product routes are obvious and functional.
- done criteria:
  - Benchmark reads like a product strategy console, not only a static report.
  - High-priority actions are easier to spot than supporting evidence.

## Risks And Dependencies

- This increment depends on the shared shell/design-system work; otherwise these routes will repeat bespoke styling again.
- Benchmark route compression must not hide evidence that current tests rely on locating.

## Validation Plan

- `mix test test/attractor_phoenix_web/live/pipeline_library_live_test.exs`
- `mix test test/attractor_phoenix_web/live/setup_live_test.exs`
- `mix test test/attractor_phoenix_web/live/benchmark_live_test.exs`
- Manual route-to-route continuity review

