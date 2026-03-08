# `AttractorEx.Edge`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/edge.ex#L1)

Runtime representation of a directed edge between two nodes.

In addition to the raw attribute map, edges expose normalized `condition` and
`status` fields used directly by the routing logic in `AttractorEx.Engine`.

# `t`

```elixir
@type t() :: %AttractorEx.Edge{
  attrs: map(),
  condition: String.t() | nil,
  from: String.t(),
  status: String.t() | nil,
  to: String.t()
}
```

# `new`

Builds a normalized edge struct from raw DOT attributes.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
