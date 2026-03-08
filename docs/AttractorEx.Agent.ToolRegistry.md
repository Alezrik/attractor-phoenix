# `AttractorEx.Agent.ToolRegistry`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/agent/tool_registry.ex#L1)

Lightweight registry of agent tools keyed by name.

# `t`

```elixir
@type t() :: %{optional(String.t()) =&gt; AttractorEx.Agent.Tool.t()}
```

# `from_tools`

```elixir
@spec from_tools([AttractorEx.Agent.Tool.t()]) :: t()
```

Builds a registry map from a tool list.

# `get`

```elixir
@spec get(t(), String.t()) :: AttractorEx.Agent.Tool.t() | nil
```

Fetches a tool by name.

# `register`

```elixir
@spec register(t(), AttractorEx.Agent.Tool.t()) :: t()
```

Registers or replaces a tool in the registry.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
