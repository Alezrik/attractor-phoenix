# AttractorExPhx

`AttractorExPhx` is the Phoenix adapter layer for `AttractorEx`.

It exists to keep the core engine in `lib/attractor_ex/` framework-agnostic while still giving a Phoenix application a clear, supported integration seam.

## Role in the Architecture

The repository is now split into three distinct layers:

1. `AttractorEx` for the standalone pipeline engine and spec-facing runtime behavior.
2. `AttractorExPhx` for Phoenix-oriented integration concerns.
3. `AttractorPhoenixWeb` for the UI, controllers, and LiveViews.

That means Phoenix code should depend on `AttractorExPhx`, not reach directly into the lower-level integration details unless it is working on the engine itself.

## Main Modules

1. `AttractorExPhx`
   - Small public facade for the adapter layer.
   - Delegates direct execution to `AttractorEx.run/3`.
   - Re-exports the HTTP client helpers for Phoenix-facing callers.

2. `AttractorExPhx.Client`
   - Req-based client for the `AttractorEx` HTTP control plane.
   - Used by LiveViews and other Phoenix processes that need to list pipelines, create runs, inspect status, answer questions, or fetch graph output.

3. `AttractorExPhx.HTTPServer`
   - Supervision-friendly wrapper around `AttractorEx.start_http_server/1`.
   - Intended for placement in a Phoenix application's supervision tree.

## Expected Integration Path

Typical Phoenix usage should look like this:

1. Start the HTTP service with `AttractorExPhx.HTTPServer` in the application supervisor.
2. Use `AttractorExPhx.Client` from LiveViews or controllers when talking to the HTTP API.
3. Use `AttractorExPhx.run/3` when a Phoenix controller or process needs direct in-process execution instead of the HTTP transport.

## Example

```elixir
children = [
  {AttractorExPhx.HTTPServer,
   port: 4101,
   ip: {127, 0, 0, 1},
   manager: MyApp.AttractorHTTP.Manager,
   registry: MyApp.AttractorHTTP.Registry,
   name: MyApp.AttractorHTTPServer}
]

{:ok, result} =
  AttractorExPhx.run(dot_source, %{}, logs_root: "tmp/runs")

{:ok, %{"pipeline_id" => pipeline_id}} =
  AttractorExPhx.create_pipeline(dot_source, %{})
```

## Test Coverage

The adapter has its own tests under `test/attractor_ex_phx/` so the Phoenix integration contract is validated independently from the engine tests and the LiveView UI tests.
