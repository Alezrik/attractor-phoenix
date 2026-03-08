# `AttractorEx.Handler`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/handler.ex#L1)

Behaviour implemented by all executable node handlers.

Handlers receive the normalized node, current context, full graph, stage directory,
and runtime options, and must return an `AttractorEx.Outcome`.

# `execute`

```elixir
@callback execute(
  AttractorEx.Node.t(),
  map(),
  AttractorEx.Graph.t(),
  String.t(),
  keyword()
) ::
  AttractorEx.Outcome.t()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
