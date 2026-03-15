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

3. `AttractorExPhx.PubSub`
   - Phoenix PubSub bridge for push-style pipeline updates.
   - Gives LiveViews and other OTP processes a native subscription interface without polling the HTTP API.
   - Supports replay-filtered snapshots through `after_sequence:` on subscribe calls.

4. `AttractorExPhx.HTTPServer`
   - Supervision-friendly wrapper around `AttractorEx.start_http_server/1`.
   - Intended for placement in a Phoenix application's supervision tree.

## Expected Integration Path

Typical Phoenix usage should look like this:

1. Start the HTTP service with `AttractorExPhx.HTTPServer` in the application supervisor.
2. Start `AttractorExPhx.PubSub` in the supervision tree when Phoenix processes need push updates.
3. Use `AttractorExPhx.Client` from LiveViews or controllers when talking to the HTTP API.
4. Use `AttractorExPhx.run/3` when a Phoenix controller or process needs direct in-process execution instead of the HTTP transport.

In this application, the LiveView dashboard consumes the pending-question API and maps
`wait.human` metadata into browser-native answer controls, so Phoenix users can resolve
human gates without dropping down to raw HTTP calls.

## Example

```elixir
children = [
  {AttractorExPhx.PubSub,
   pubsub_server: MyApp.PubSub,
   manager: MyApp.AttractorHTTP.Manager,
   name: MyApp.AttractorPubSubBridge},
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

{:ok, snapshot} =
  AttractorExPhx.subscribe_pipeline(pipeline_id,
    pubsub_server: MyApp.PubSub,
    bridge: MyApp.AttractorPubSubBridge,
    after_sequence: 10
  )

receive do
  {:attractor_ex_event, event} ->
    IO.inspect({snapshot["status"], event["type"]})
end
```

## Test Coverage

The adapter has its own tests under `test/attractor_ex_phx/` so the Phoenix integration contract is validated independently from the engine tests and the LiveView UI tests.
