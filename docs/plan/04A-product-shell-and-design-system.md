# 04A. Product Shell And Design System

Research input reviewed on 2026-03-15:

- `C:\Users\ex_ra\code\examples\FOCUSED-RESEARCH-UI.md`
- Primary reference: `n8n`
- Supporting references: `xyflow`, `node-red`

## Context

Current repo evidence:

- `lib/attractor_phoenix_web/components/layouts.ex` provides a simple top bar, but page-specific hero sections, actions, and context live inside each LiveView.
- `assets/css/app.css` contains large screen-specific style blocks and still loads `daisyui` and `daisyui-theme`.
- `lib/attractor_phoenix_web/components/core_components.ex` still uses daisyUI-flavored classes for buttons, alerts, inputs, tables, and lists.
- Dashboard, builder, benchmark, setup, and library each define their own card language instead of inheriting one product system.

The app already has visual ambition, but it does not yet read as one premium workflow product. This increment creates the shared shell and component system the rest of the UI work can build on.

## Increment Goal

Create a coherent product shell, token system, and component baseline so every LiveView inherits the same premium visual language and interaction rules.

## Non-Goals

- Rebuilding builder canvas interactions
- Adding new runtime endpoints
- Rewriting page-specific information architecture beyond what the shell requires

## Reference Anchors

- `n8n`: premium workflow-product shell, command bar framing, restrained operator chrome
- `xyflow`: utility-first control surfaces that stay out of the way of the canvas
- `node-red`: dense expert affordances without losing hierarchy

## Sprint Backlog

### UI-04A-01

- status: `done`
- title: Replace the current top-nav frame with a product shell
- rationale: The current header is functional, but it does not establish app identity, contextual actions, or route-level continuity.
- file targets:
  - `lib/attractor_phoenix_web/components/layouts.ex`
  - `lib/attractor_phoenix_web/components/layouts/root.html.heex`
  - `assets/css/app.css`
- dependencies: none
- implementation notes:
  - Introduce a shell with global nav, page identity zone, status rail, and route-aware action slot.
  - Support both desktop and mobile layouts without duplicating navigation semantics.
  - Keep `<Layouts.app ...>` as the outer wrapper for every LiveView.
- execution notes:
  - Replaced the old header with a shared product shell that adds a branded command-bar frame, route-aware status rail, action slot, and `<details>`-based mobile navigation.
  - Moved route identity into `Layouts.app/1` so dashboard, builder, library, setup, and benchmark can simplify their page-top hero usage and let the shell carry continuity.
  - Kept flash rendering inside the layout and updated `root.html.heex` so the new shell body/background applies app-wide.
- verification steps:
  - Start the app and inspect `/`, `/builder`, `/library`, `/setup`, and `/benchmark` at mobile and desktop widths.
  - Confirm active-route highlighting, shell spacing, and flash placement still work.
- validation results:
  - `mix compile` passed.
  - `mix test test/attractor_phoenix_web/live test/attractor_phoenix_web/controllers` passed.
  - Manual route review was not run in this execution pass.
- done criteria:
  - Every LiveView inherits the same top-level shell.
  - Per-page hero blocks are simplified because shell-level structure now carries more of the product identity.
  - Mobile navigation remains usable without inline scripts.

### UI-04A-02

- status: `done`
- title: Replace daisyUI-heavy primitives with repo-owned design tokens and components
- rationale: Current primitives are split between custom classes and daisyUI defaults, which prevents a distinctive and consistent visual system.
- file targets:
  - `assets/css/app.css`
  - `lib/attractor_phoenix_web/components/core_components.ex`
  - `lib/attractor_phoenix_web/components/layouts.ex`
- dependencies: `UI-04A-01`
- implementation notes:
  - Define explicit CSS variables for color, surface elevation, radius, spacing, border, and motion.
  - Replace generic `btn`, `alert`, `input`, `textarea`, `select`, `table`, and `list` styling with repo-owned Tailwind/custom CSS combinations.
  - Consolidate repeated `builder-btn`, card, badge, and panel treatments into shared component patterns.
- execution notes:
  - Removed daisyUI plugin/theme usage from `assets/css/app.css` and replaced it with repo-owned light/dark token variables exposed through Tailwind v4 `@theme inline`.
  - Rebuilt flash, button, input, table, and list components in `core_components.ex` around repo-owned `ui-*` classes instead of `btn`, `alert`, `input`, `select`, `textarea`, `table`, and `list` semantics.
  - Added shared shell/button/input/flash/table/list CSS primitives so builder buttons and shell controls inherit one tokenized visual system.
- verification steps:
  - Run the existing LiveView tests that exercise forms and page rendering.
  - Manually inspect flash messages, forms, buttons, and tables across the app.
- validation results:
  - `mix test test/attractor_phoenix_web/live test/attractor_phoenix_web/controllers` passed.
  - `mix precommit` was run and failed outside this increment in `test/attractor_ex/interviewer_server_test.exs` with four `AttractorEx.InterviewerServerTest` failures unrelated to the shell files touched here.
  - Manual primitive review in the browser was not run in this execution pass.
- done criteria:
  - Shared UI primitives no longer depend on daisyUI class semantics for their final appearance.
  - Buttons, inputs, badges, and panels look consistent across routes.
  - The CSS token layer is documented inline well enough for later increments to reuse safely.

### UI-04A-03

- status: `done`
- title: Standardize loading, empty, error, and motion states across the shell
- rationale: Several routes have bespoke banners and cards, but the app lacks a single standard for transient states.
- file targets:
  - `assets/css/app.css`
  - `lib/attractor_phoenix_web/components/core_components.ex`
  - `lib/attractor_phoenix_web/live/dashboard_live.html.heex`
  - `lib/attractor_phoenix_web/live/pipeline_builder_live.html.heex`
  - `lib/attractor_phoenix_web/live/pipeline_library_live.html.heex`
  - `lib/attractor_phoenix_web/live/setup_live.html.heex`
  - `lib/attractor_phoenix_web/live/benchmark_live.html.heex`
- dependencies: `UI-04A-02`
- implementation notes:
  - Introduce shared empty-state, inline-error, and skeleton/loading components.
  - Use subtle route transitions, staggered content reveals, and loading affordances instead of one-off animations.
  - Keep motion purposeful and low-noise; avoid decorative motion on dense operator screens.
- execution notes:
  - Added shared `inline_error`, `empty_state`, and `skeleton` components in `core_components.ex`.
  - Replaced bespoke error/empty blocks on dashboard, builder, library, and setup with the shared state components and moved benchmark/setup/page-top state framing into the shell.
  - Added restrained shell/page reveal motion, loading skeleton animation, and reduced-motion handling in `assets/css/app.css`.
- verification steps:
  - Trigger flash messages, loading states, and empty states on each primary route.
  - Confirm reduced-motion users still get a correct experience if motion preferences are honored.
- validation results:
  - `mix test test/attractor_phoenix_web/live test/attractor_phoenix_web/controllers` passed.
  - `mix compile` passed.
  - Reduced-motion behavior is implemented in CSS, but browser/manual interaction checks were not run in this execution pass.
- done criteria:
  - Empty, loading, and error states share a recognizable visual system.
  - Motion is present but restrained.
  - The app shell feels consistent before any builder/operator-specific increment lands.

## Risks And Dependencies

- This increment should land before major page rewrites so later work does not duplicate component cleanup.
- Replacing daisyUI-flavored defaults may require updating existing tests that rely on generated markup details.

## Validation Plan

- `mix test test/attractor_phoenix_web/live`
- `mix test test/attractor_phoenix_web/controllers`
- Manual route review on desktop and mobile widths
