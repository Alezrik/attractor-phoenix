# `AttractorEx.Parser`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/parser.ex#L1)

Parses the supported Attractor DOT subset into `AttractorEx.Graph`.

The parser focuses on the executable subset used by the engine rather than full
Graphviz grammar parity. It also finalizes parsed graphs by applying model stylesheet
rules and normalizing nodes into runtime structs.

# `parse_scope`

```elixir
@type parse_scope() :: %{
  node_defaults: map(),
  edge_defaults: map(),
  classes: [String.t()],
  graph_attrs: map()
}
```

# `parse`

Parses DOT source into a normalized `AttractorEx.Graph`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
