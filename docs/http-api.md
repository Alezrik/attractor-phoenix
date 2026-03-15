# HTTP API

`AttractorEx.HTTP` exposes a lightweight Bandit-backed service for running pipelines remotely.

## Main Entry Point

Start the service with:

```elixir
{:ok, pid} = AttractorEx.start_http_server(port: 4041)
```

This starts:

- `AttractorEx.HTTP.Manager` for durable pipeline state
- a duplicate-key `Registry` for event subscribers
- `AttractorEx.HTTP.Router` for the HTTP surface

By default the manager persists runtime state under `tmp/attractor_http_store`. Pass
`store_root: ...` to `AttractorEx.start_http_server/1` when you need a different
location.

## Primary Endpoints

The router exposes these endpoints:

- `POST /pipelines`
- `GET /pipelines`
- `GET /pipelines/:id`
- `GET /pipelines/:id/events`
- `POST /pipelines/:id/cancel`
- `GET /pipelines/:id/graph`
- `GET /pipelines/:id/questions`
- `POST /pipelines/:id/questions/:qid/answer`
- `GET /pipelines/:id/checkpoint`
- `GET /pipelines/:id/context`

It also includes definition-of-done compatibility aliases:

- `POST /run`
- `GET /status`
- `POST /answer`

## Event Streaming

`GET /pipelines/:id/events` supports both:

- JSON polling
- server-sent events when streaming is enabled
- replay windows via `?after=<sequence>` for either mode

The HTTP manager records engine events like:

- `PipelineStarted`
- `StageStarted`
- `CheckpointSaved`
- `StageCompleted`
- `StageFailed`
- `PipelineCompleted`
- `PipelineFailed`

Each persisted event includes a monotonic `sequence` so clients can resume event
consumption after reconnects or process restarts.

## Graph Rendering

`GET /pipelines/:id/graph` supports multiple formats:

- `svg`
- `dot`
- `json`
- `mermaid`
- `text`

`AttractorEx.HTTP.GraphRenderer` is responsible for the non-DOT renderings.

## Human Gate Integration

When service mode is used, `AttractorEx.HTTP.Manager` runs pipelines with `AttractorEx.Interviewers.Server`, which means `wait.human` questions become pending HTTP resources that can be listed and answered out-of-process.

## Recovery and Replay

The HTTP runtime now persists:

1. run metadata
2. append-only event history
3. pending questions
4. checkpoint snapshots
5. artifact indexes for files under each run directory

On boot, persisted runs are reloaded before serving requests. Incomplete runs are
restarted from their latest checkpoint when one exists, otherwise from their initial
context.
