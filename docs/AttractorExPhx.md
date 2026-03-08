# `AttractorExPhx`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex_phx.ex#L1)

Phoenix-facing adapter layer for `AttractorEx`.

`AttractorEx` remains the standalone pipeline engine. `AttractorExPhx` is the
integration seam a Phoenix application can depend on for:

- direct pipeline execution via `run/3`
- supervision-friendly HTTP server startup via `child_spec/1` and `start_link/1`
- Req-based access to the HTTP control plane via `AttractorExPhx.Client`
- PubSub subscriptions for LiveViews and other Phoenix processes via `AttractorExPhx.PubSub`

# `answer_pipeline_question`

# `answer_question`

# `cancel_pipeline`

# `child_spec`

```elixir
@spec child_spec(keyword()) :: Supervisor.child_spec()
```

# `create_pipeline`

# `get_pipeline`

# `get_pipeline_checkpoint`

# `get_pipeline_context`

# `get_pipeline_events`

# `get_pipeline_graph`

# `get_pipeline_graph_dot`

# `get_pipeline_graph_json`

# `get_pipeline_graph_mermaid`

# `get_pipeline_graph_svg`

# `get_pipeline_graph_text`

# `get_pipeline_questions`

# `get_status`

# `list_pipelines`

# `pipeline_topic`

# `run`

```elixir
@spec run(String.t(), map(), keyword()) ::
  {:ok, map()}
  | {:error, %{diagnostics: list()}}
  | {:error, %{error: String.t()}}
```

# `run_pipeline`

# `start_http_server`

```elixir
@spec start_http_server(keyword()) :: {:ok, pid()} | {:error, term()}
```

# `start_link`

```elixir
@spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
```

# `stop_http_server`

```elixir
@spec stop_http_server(pid() | atom()) :: :ok
```

# `subscribe_pipeline`

# `unsubscribe_pipeline`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
