# `AttractorEx.Outcome`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/outcome.ex#L1)

Standard result value returned by node handlers.

Outcomes tell the engine whether a stage succeeded, partially succeeded, failed, or
should be retried. They also carry context updates and routing hints such as
`preferred_label` and `suggested_next_ids`.

# `failure_category`

```elixir
@type failure_category() :: :retryable | :terminal | :pipeline | nil
```

# `status`

```elixir
@type status() :: :success | :partial_success | :fail | :retry
```

# `t`

```elixir
@type t() :: %AttractorEx.Outcome{
  context_updates: map(),
  failure_category: failure_category(),
  failure_reason: String.t() | nil,
  notes: String.t() | nil,
  preferred_label: String.t() | nil,
  status: status(),
  suggested_next_ids: [String.t()]
}
```

# `fail`

Builds a failure outcome with a reason and failure category.

# `partial_success`

Builds a partial-success outcome with optional context updates and notes.

# `retry`

Builds a retry outcome with a reason and retry category.

# `success`

Builds a success outcome with optional context updates and notes.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
