# `AttractorEx.Node`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/node.ex#L1)

Runtime representation of a pipeline node.

Nodes keep the original attribute map and the normalized fields that drive execution,
such as shape, handler type, prompt, goal-gate status, and retry targets.

# `t`

```elixir
@type t() :: %AttractorEx.Node{
  attrs: map(),
  fallback_retry_target: String.t() | nil,
  goal_gate: boolean(),
  id: String.t(),
  prompt: String.t(),
  retry_target: String.t() | nil,
  shape: String.t(),
  type: String.t()
}
```

# `handler_type_for_shape`

Returns the default handler type implied by a Graphviz shape.

# `new`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
