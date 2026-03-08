# `AttractorEx.Agent.LocalExecutionEnvironment`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/agent/local_execution_environment.ex#L1)

Local filesystem-backed execution environment for agent sessions.

It exposes a working directory, platform information, and the built-in
filesystem/shell primitives used by the coding-agent loop.

# `t`

```elixir
@type t() :: %AttractorEx.Agent.LocalExecutionEnvironment{
  env: %{optional(String.t()) =&gt; String.t()},
  working_dir: String.t() | nil
}
```

# `new`

```elixir
@spec new(keyword()) :: t()
```

Builds a local execution environment.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
