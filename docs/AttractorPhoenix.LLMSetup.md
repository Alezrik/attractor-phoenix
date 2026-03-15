# `AttractorPhoenix.LLMSetup`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_phoenix/llm_setup.ex#L1)

File-backed storage for provider API keys, discovered models, and default model selection.

# `provider_entry`

```elixir
@type provider_entry() :: %{
  id: String.t(),
  api_key: String.t(),
  mode: String.t(),
  cli_command: String.t(),
  models: [map()],
  last_error: String.t() | nil,
  last_synced_at: String.t() | nil
}
```

# `settings`

```elixir
@type settings() :: %{
  providers: %{optional(String.t()) =&gt; provider_entry()},
  default_provider: String.t() | nil,
  default_model: String.t() | nil
}
```

# `available_models`

```elixir
@spec available_models() :: [map()]
```

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `default_selection`

```elixir
@spec default_selection() :: %{provider: String.t() | nil, model: String.t() | nil}
```

# `get_settings`

```elixir
@spec get_settings() :: settings()
```

# `provider_api_key`

```elixir
@spec provider_api_key(String.t()) :: String.t() | nil
```

# `provider_cli_command`

```elixir
@spec provider_cli_command(String.t()) :: String.t() | nil
```

# `provider_mode`

```elixir
@spec provider_mode(String.t()) :: String.t()
```

# `refresh_models`

```elixir
@spec refresh_models() :: {:ok, settings()} | {:error, String.t()}
```

# `reset`

```elixir
@spec reset() :: :ok
```

# `save_api_keys`

```elixir
@spec save_api_keys(map()) :: {:ok, settings()} | {:error, String.t()}
```

# `set_default`

```elixir
@spec set_default(String.t(), String.t()) :: {:ok, settings()} | {:error, String.t()}
```

# `start_link`

```elixir
@spec start_link(keyword()) :: GenServer.on_start()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
