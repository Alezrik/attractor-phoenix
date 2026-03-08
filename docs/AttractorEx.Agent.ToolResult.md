# `AttractorEx.Agent.ToolResult`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/agent/tool_result.ex#L1)

Normalized representation of a tool execution result fed back to the model.

# `t`

```elixir
@type t() :: %AttractorEx.Agent.ToolResult{
  content: String.t(),
  is_error: boolean(),
  tool_call_id: String.t() | nil
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
