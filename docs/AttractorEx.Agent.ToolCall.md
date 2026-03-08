# `AttractorEx.Agent.ToolCall`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/agent/tool_call.ex#L1)

Normalized representation of a tool call requested by the model.

# `t`

```elixir
@type t() :: %AttractorEx.Agent.ToolCall{
  arguments: map() | String.t(),
  id: String.t() | nil,
  name: String.t()
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
