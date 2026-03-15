# `AttractorEx.HTTP.ArtifactRecord`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/http/artifact_record.ex#L1)

Typed artifact metadata for persisted HTTP-managed pipeline runs.

# `t`

```elixir
@type t() :: %AttractorEx.HTTP.ArtifactRecord{
  kind: String.t(),
  path: String.t(),
  size: non_neg_integer(),
  updated_at: String.t()
}
```

# `from_map`

```elixir
@spec from_map(map()) :: t()
```

# `index_run_artifacts`

```elixir
@spec index_run_artifacts(String.t(), String.t()) :: [t()]
```

# `to_map`

```elixir
@spec to_map(t()) :: map()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
