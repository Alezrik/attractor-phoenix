# `AttractorEx.HTTP.CheckpointRecord`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/http/checkpoint_record.ex#L1)

Typed checkpoint snapshot persisted by the HTTP runtime manager.

# `t`

```elixir
@type t() :: %AttractorEx.HTTP.CheckpointRecord{
  completed_nodes: [String.t()],
  context: map(),
  current_node: String.t() | nil,
  timestamp: String.t()
}
```

# `from_map`

```elixir
@spec from_map(map()) :: t()
```

# `to_map`

```elixir
@spec to_map(t()) :: map()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
