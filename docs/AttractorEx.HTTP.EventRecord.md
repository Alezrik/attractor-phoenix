# `AttractorEx.HTTP.EventRecord`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/http/event_record.ex#L1)

Typed persisted event entry for HTTP-managed pipeline runs.

# `t`

```elixir
@type t() :: %AttractorEx.HTTP.EventRecord{
  payload: map(),
  pipeline_id: String.t(),
  sequence: pos_integer(),
  status: String.t() | atom() | nil,
  timestamp: String.t(),
  type: String.t()
}
```

# `from_map`

```elixir
@spec from_map(map()) :: t()
```

# `new`

```elixir
@spec new(String.t(), pos_integer(), map()) :: t()
```

# `serialize`

```elixir
@spec serialize(t()) :: map()
```

# `to_map`

```elixir
@spec to_map(t()) :: map()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
