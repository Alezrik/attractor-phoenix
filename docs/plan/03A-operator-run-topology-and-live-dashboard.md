# 03A. Operator Run Topology And Live Dashboard

Research input reviewed on 2026-03-15:

- `C:\Users\ex_ra\code\examples\FOCUSED-RESEARCH-UI.md`
- Primary reference: `n8n`
- Supporting reference: `node-red`

## Context

Current repo evidence:

- `lib/attractor_phoenix_web/live/dashboard_live.ex` refreshes with `Process.send_after/3` every 3 seconds.
- `lib/attractor_phoenix_web/channels/attractor_channel.ex` already exists, but the operator LiveViews are not yet built around subscription-driven updates.
- `lib/attractor_phoenix_web/live/dashboard_live.html.heex` places list, summary, questions, events, payloads, and graph formats on one route behind a query-param patch.

The current dashboard is informative, but it behaves like a polling report. This increment turns it into a live run center with clearer topology.

## Increment Goal

Create a live operator surface with a dedicated run list, deep-linkable run detail, and event-driven updates as the default path.

## Non-Goals

- Full debugger timeline and diff tooling
- Rebuilding builder canvas interactions
- Adding new transport APIs if existing PubSub/channel wiring is sufficient

## Reference Anchors

- `n8n`: product-grade continuity between list views, run views, and execution status
- `node-red`: dense operational clarity when many flows are present

## Sprint Backlog

### UI-03A-01

- status: `done`
- title: Split the dashboard into run list and run detail topology
- rationale: One large page currently carries too many responsibilities and weakens deep linking.
- file targets:
  - `lib/attractor_phoenix_web/router.ex`
  - `lib/attractor_phoenix_web/live/dashboard_live.ex`
  - `lib/attractor_phoenix_web/live/dashboard_live.html.heex`
  - `lib/attractor_phoenix_web/live/run_live.ex`
  - `lib/attractor_phoenix_web/live/run_live.html.heex`
- dependencies: `04A-product-shell-and-design-system.md`
- implementation notes:
  - Keep `/` as the operator overview and add a dedicated route for a selected run.
  - Move dense payload inspection off the overview route and into the run detail route.
  - Preserve deep links from builder run results into the new run detail view.
- execution notes:
  - Split the operator surface into `/` for queue-level monitoring and `/runs/:id` for payload-heavy inspection.
  - Added shared run-loading helpers so overview and detail pages consume one consistent runtime data contract.
  - Linked builder run results into the dedicated run detail route to preserve deep-link continuity.
- verification steps:
  - Navigate from the dashboard to a run detail route and refresh the page directly on the deep link.
  - Confirm the overview page stays useful when many runs exist.
- validation results:
  - Added LiveView coverage for direct `live(conn, ~p"/runs/:id")` loading and builder-to-run-detail navigation.
  - Verified the route split with `mix test test/attractor_phoenix_web/live/dashboard_live_test.exs test/attractor_phoenix_web/live/pipeline_builder_live_test.exs`.
- done criteria:
  - Operators can bookmark and share a specific run URL.
  - Overview and detail views each have a focused job.

### UI-03A-02

- status: `done`
- title: Replace polling-first updates with subscription-first LiveView updates
- rationale: The repo already exposes pipeline subscription plumbing, but the UI still polls by default.
- file targets:
  - `lib/attractor_phoenix_web/live/dashboard_live.ex`
  - `lib/attractor_phoenix_web/live/run_live.ex`
  - `lib/attractor_phoenix_web/channels/attractor_channel.ex`
  - `assets/js/app.js`
- dependencies: `UI-03A-01`
- implementation notes:
  - Subscribe operator views to pipeline updates and only fall back to polling when subscriptions are unavailable.
  - Surface connection state in the UI so operators know whether they are live or degraded.
  - Keep refresh logic isolated so later debugger views can reuse it.
- execution notes:
  - Switched overview and detail LiveViews to server-side pipeline subscriptions through `AttractorExPhx.subscribe_pipeline/1`.
  - Added a small `OperatorConnection` hook in `assets/js/app.js` so the UI can reflect `live`, `reconnecting`, and polling fallback states.
  - Kept `Process.send_after/3` only as a fallback path when subscriptions cannot be established.
- verification steps:
  - Start a run and confirm overview and detail surfaces update without waiting for the polling interval.
  - Simulate disconnect behavior and confirm fallback state is visible.
- validation results:
  - Confirmed operator views compile and pass LiveView tests under subscription-first refresh logic.
  - `mix precommit` passed after the new subscription and fallback wiring landed.
- done criteria:
  - Live updates are the normal path.
  - Operators can tell whether the view is live, reconnecting, or stale.

### UI-03A-03

- status: `done`
- title: Add run list filtering, status segmentation, and compact summary cards
- rationale: The current list is serviceable for a few runs, but it will not scale into a real operator console.
- file targets:
  - `lib/attractor_phoenix_web/live/dashboard_live.ex`
  - `lib/attractor_phoenix_web/live/dashboard_live.html.heex`
  - `assets/css/app.css`
  - `test/attractor_phoenix_web/live/dashboard_live_test.exs`
- dependencies: `UI-03A-01`
- implementation notes:
  - Add status filters, question-state filters, and search by pipeline id.
  - Keep summary cards compact and scannable rather than oversized hero statistics.
  - Use visual hierarchy that prioritizes live state, failures, and pending human work.
- execution notes:
  - Added operator filters for status, pending-question state, and pipeline-id search on the overview route.
  - Reworked the overview list into compact run rows with elevated failure/question badges and summary cards for queue health.
  - Added dedicated dashboard LiveView tests for filtering, deep-link loading, and question form rendering.
- verification steps:
  - Filter the run list by status and search by pipeline id.
  - Confirm selected-run routing still works when the list is filtered.
- validation results:
  - Added `test/attractor_phoenix_web/live/dashboard_live_test.exs` covering status filtering, search, deep links, and multi-select human input rendering.
  - `mix test test/attractor_phoenix_web/live/dashboard_live_test.exs test/attractor_phoenix_web/live/pipeline_builder_live_test.exs` passed.
- done criteria:
  - The run list remains usable as volume increases.
  - Failed and blocked runs are easier to spot than successful noise.

## Risks And Dependencies

- If the existing channel/PubSub payloads are too thin, record that as a dependency rather than hiding it in UI work.
- Route split changes navigation assumptions across the builder and dashboard.

## Validation Plan

- `mix test test/attractor_phoenix_web/live/dashboard_live_test.exs`
- Manual live update smoke test with active pipeline changes
