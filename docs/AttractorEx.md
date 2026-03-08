# `AttractorEx`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex.ex#L1)

Public entry point for the AttractorEx pipeline engine.

`AttractorEx` exposes the stable API for parsing, validating, executing, resuming,
and serving DOT-defined Attractor pipelines.

## Main APIs

- `run/3` executes a new pipeline
- `resume/3` resumes from a checkpoint
- `validate/2` returns diagnostics without execution
- `validate_or_raise/2` escalates validation errors
- `start_http_server/1` exposes the engine over HTTP

# `resume`

```elixir
@spec resume(String.t(), String.t() | map(), keyword()) ::
  {:ok, map()}
  | {:error, %{diagnostics: list()}}
  | {:error, %{error: String.t()}}
```

Resumes execution from a checkpoint struct, map, or `checkpoint.json` path.

# `run`

```elixir
@spec run(String.t(), map(), keyword()) ::
  {:ok, map()}
  | {:error, %{diagnostics: list()}}
  | {:error, %{error: String.t()}}
```

Parses, validates, and executes a pipeline graph from scratch.

# `start_http_server`

```elixir
@spec start_http_server(keyword()) :: {:ok, pid()} | {:error, term()}
```

Starts the lightweight Bandit-backed AttractorEx HTTP service.

# `stop_http_server`

```elixir
@spec stop_http_server(pid() | atom()) :: :ok
```

Stops a previously started AttractorEx HTTP server.

# `validate`

```elixir
@spec validate(
  String.t() | AttractorEx.Graph.t(),
  keyword()
) :: list() | {:error, %{error: String.t()}}
```

Validates a DOT string or normalized graph and returns diagnostics.

# `validate_or_raise`

```elixir
@spec validate_or_raise(
  String.t() | AttractorEx.Graph.t(),
  keyword()
) :: list()
```

Validates a DOT string or graph and raises on error-severity diagnostics.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
