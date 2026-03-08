# `AttractorEx.Graph`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/graph.ex#L1)

Normalized in-memory representation of a parsed pipeline graph.

A graph carries graph-level attributes, node and edge defaults, a node map, and a
flat edge list. `AttractorEx.Parser` produces this struct, `AttractorEx.Validator`
checks it, and `AttractorEx.Engine` executes it.

# `t`

```elixir
@type t() :: %AttractorEx.Graph{
  attrs: map(),
  edge_defaults: map(),
  edges: list(),
  id: String.t(),
  node_defaults: map(),
  nodes: map()
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
