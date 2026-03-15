# `AttractorEx.HTTP.RunRecord`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/http/run_record.ex#L1)

Typed persisted pipeline run metadata for the HTTP runtime.

# `t`

```elixir
@type t() :: %AttractorEx.HTTP.RunRecord{
  artifacts: [AttractorEx.HTTP.ArtifactRecord.t()],
  checkpoint: AttractorEx.HTTP.CheckpointRecord.t() | nil,
  context: map(),
  dot: String.t(),
  error: term(),
  execution_opts: keyword(),
  id: String.t(),
  initial_context: map(),
  inserted_at: String.t(),
  logs_root: String.t(),
  result: map() | nil,
  status: atom() | String.t(),
  updated_at: String.t()
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
