# `AttractorEx.HTTP.QuestionRecord`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/http/question_record.ex#L1)

Typed persisted question metadata for HTTP-managed human gates.

# `t`

```elixir
@type t() :: %AttractorEx.HTTP.QuestionRecord{
  id: String.t(),
  inserted_at: String.t(),
  metadata: map(),
  multiple: boolean() | nil,
  options: [map()],
  ref: reference() | nil,
  required: boolean() | nil,
  text: String.t() | nil,
  timeout_seconds: number() | nil,
  type: String.t() | nil,
  waiter: pid() | nil
}
```

# `from_map`

```elixir
@spec from_map(map()) :: t()
```

# `serialize`

```elixir
@spec serialize(t()) :: map()
```

# `to_public_map`

```elixir
@spec to_public_map(t()) :: map()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
