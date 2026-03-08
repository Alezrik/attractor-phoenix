# `AttractorEx.ModelStylesheet`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/model_stylesheet.ex#L1)

Parses and applies the `model_stylesheet` graph attribute.

AttractorEx supports both legacy JSON-style stylesheets and a CSS-like selector
syntax. Styles are resolved before validation so the validator and engine see the
same effective node attributes.

# `lint_diagnostic`

```elixir
@type lint_diagnostic() :: %{
  severity: :warning,
  code: atom(),
  message: String.t(),
  node_id: nil
}
```

# `rule`

```elixir
@type rule() :: %{
  selector: String.t(),
  attrs: map(),
  rank: integer(),
  order: integer()
}
```

# `attrs_for_node`

Resolves the effective stylesheet attributes for a node.

# `lint`

Returns non-fatal stylesheet diagnostics.

# `parse`

Parses a stylesheet definition into ranked rules.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
