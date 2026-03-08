# `AttractorEx.Agent.ExecutionEnvironment`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/agent/execution_environment.ex#L1)

Execution-environment behaviour for coding-agent sessions.

The contract intentionally mirrors the core local tooling surface exposed by
the agent loop: filesystem reads and writes, directory listing and globbing,
text search, shell command execution, and a small amount of host metadata.

# `environment_context`

```elixir
@callback environment_context(term()) :: map()
```

# `glob`

```elixir
@callback glob(term(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
```

# `grep`

```elixir
@callback grep(term(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
```

# `list_directory`

```elixir
@callback list_directory(term(), String.t()) :: {:ok, [map()]} | {:error, term()}
```

# `platform`

```elixir
@callback platform(term()) :: String.t()
```

# `read_file`

```elixir
@callback read_file(term(), String.t()) :: {:ok, String.t()} | {:error, term()}
```

# `shell_command`

```elixir
@callback shell_command(term(), String.t(), keyword()) ::
  {:ok, %{output: String.t(), exit_code: integer(), truncated?: boolean()}}
  | {:error, term()}
```

# `working_directory`

```elixir
@callback working_directory(term()) :: String.t()
```

# `write_file`

```elixir
@callback write_file(term(), String.t(), String.t()) :: :ok | {:error, term()}
```

# `environment_context`

```elixir
@spec environment_context(term()) :: map()
```

# `glob`

```elixir
@spec glob(term(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
```

# `grep`

```elixir
@spec grep(term(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
```

# `implementation?`

```elixir
@spec implementation?(term()) :: boolean()
```

# `list_directory`

```elixir
@spec list_directory(term(), String.t()) :: {:ok, [map()]} | {:error, term()}
```

# `platform`

```elixir
@spec platform(term()) :: String.t()
```

# `read_file`

```elixir
@spec read_file(term(), String.t()) :: {:ok, String.t()} | {:error, term()}
```

# `shell_command`

```elixir
@spec shell_command(term(), String.t(), keyword()) ::
  {:ok, %{output: String.t(), exit_code: integer(), truncated?: boolean()}}
  | {:error, term()}
```

# `working_directory`

```elixir
@spec working_directory(term()) :: String.t()
```

# `write_file`

```elixir
@spec write_file(term(), String.t(), String.t()) :: :ok | {:error, term()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
