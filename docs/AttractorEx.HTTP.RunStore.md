# `AttractorEx.HTTP.RunStore`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/http/run_store.ex#L1)

Behaviour for durable HTTP runtime storage.

# `config`

```elixir
@type config() :: term()
```

# `loaded_run`

```elixir
@type loaded_run() :: %{
  run: AttractorEx.HTTP.RunRecord.t(),
  events: [AttractorEx.HTTP.EventRecord.t()],
  questions: [AttractorEx.HTTP.QuestionRecord.t()]
}
```

# `append_event`

```elixir
@callback append_event(config(), String.t(), AttractorEx.HTTP.EventRecord.t()) ::
  :ok | {:error, term()}
```

# `init`

```elixir
@callback init(keyword()) :: {:ok, config()}
```

# `list_events`

```elixir
@callback list_events(config(), String.t(), keyword()) ::
  {:ok, [AttractorEx.HTTP.EventRecord.t()]} | {:error, term()}
```

# `list_runs`

```elixir
@callback list_runs(config()) :: {:ok, [loaded_run()]} | {:error, term()}
```

# `put_questions`

```elixir
@callback put_questions(config(), String.t(), [AttractorEx.HTTP.QuestionRecord.t()]) ::
  :ok | {:error, term()}
```

# `put_run`

```elixir
@callback put_run(config(), AttractorEx.HTTP.RunRecord.t()) :: :ok | {:error, term()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
