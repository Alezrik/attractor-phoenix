# `AttractorPhoenix.PipelineLibrary`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_phoenix/pipeline_library.ex#L1)

File-backed storage for reusable builder pipelines.

Entries are persisted as JSON so the builder and `/library` LiveViews can
share saved DOT graphs without introducing a database dependency.

# `attrs`

```elixir
@type attrs() :: %{optional(String.t()) =&gt; String.t() | nil}
```

# `entry`

```elixir
@type entry() :: %{
  id: String.t(),
  name: String.t(),
  description: String.t(),
  dot: String.t(),
  context_json: String.t(),
  inserted_at: String.t(),
  updated_at: String.t()
}
```

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `create_entry`

```elixir
@spec create_entry(attrs()) :: {:ok, entry()} | {:error, map()}
```

# `delete_entry`

```elixir
@spec delete_entry(String.t()) :: :ok | {:error, :not_found}
```

# `get_entry`

```elixir
@spec get_entry(String.t()) :: {:ok, entry()} | {:error, :not_found}
```

# `list_entries`

```elixir
@spec list_entries() :: [entry()]
```

# `reset`

```elixir
@spec reset() :: :ok
```

# `start_link`

```elixir
@spec start_link(keyword()) :: GenServer.on_start()
```

# `update_entry`

```elixir
@spec update_entry(String.t(), attrs()) ::
  {:ok, entry()} | {:error, :not_found | map()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
