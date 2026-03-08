# Phoenix Adapter

`AttractorEx` stays framework-agnostic. `AttractorExPhx` is the explicit adapter layer that plugs Phoenix into the engine.

## Why This Layer Exists

The repository now has three clearer boundaries:

1. `AttractorEx` for the standalone engine, HTTP service, and spec-facing runtime behavior.
2. `AttractorExPhx` for Phoenix-oriented integration code such as supervision-friendly server startup and Req-based HTTP access.
3. `AttractorPhoenixWeb` for the UI and controller/liveview experience.

That split keeps `lib/attractor_ex/` independent while making the integration path easy to find and test on its own.

## Main Modules

- `AttractorExPhx`
- `AttractorExPhx.Client`
- `AttractorExPhx.HTTPServer`

## Typical Usage

Start the engine HTTP API under a Phoenix supervision tree:

```elixir
children = [
  {AttractorExPhx.HTTPServer,
   port: 4101,
   ip: {127, 0, 0, 1},
   manager: MyApp.AttractorHTTP.Manager,
   registry: MyApp.AttractorHTTP.Registry,
   name: MyApp.AttractorHTTPServer}
]
```

Run a pipeline directly from a Phoenix controller or other process:

```elixir
{:ok, result} = AttractorExPhx.run(dot_source, %{}, logs_root: "tmp/runs")
```

Call the HTTP control plane from LiveView:

```elixir
{:ok, %{"pipelines" => pipelines}} = AttractorExPhx.list_pipelines()
{:ok, %{"pipeline_id" => id}} = AttractorExPhx.create_pipeline(dot_source, %{})
{:ok, graph} = AttractorExPhx.get_pipeline_graph_json(id)
```

## Test Strategy

The adapter has its own test scope under `test/attractor_ex_phx/` so the integration contract can be validated without depending on the LiveView UI tests to cover it indirectly.
