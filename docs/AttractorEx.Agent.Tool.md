# `AttractorEx.Agent.Tool`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/agent/tool.ex#L1)

Definition of a callable tool exposed to an agent session.

Tools default to `target: :environment`, meaning their executor receives the
current execution environment. Session-managed tools such as subagent lifecycle
operations set `target: :session` and receive the current session instead.

# `executor`

```elixir
@type executor() :: (map(), term() -&gt; String.t() | map() | list() | term())
```

# `t`

```elixir
@type t() :: %AttractorEx.Agent.Tool{
  description: String.t(),
  execute: executor(),
  name: String.t(),
  parameters: map(),
  target: target()
}
```

# `target`

```elixir
@type target() :: :environment | :session
```

# `definition`

```elixir
@spec definition(t()) :: map()
```

Serializes a tool into the model-facing definition shape.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
