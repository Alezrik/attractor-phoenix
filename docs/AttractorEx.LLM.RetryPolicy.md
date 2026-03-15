# `AttractorEx.LLM.RetryPolicy`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/llm/retry_policy.ex#L1)

Configures client-side retry behavior for adapter failures.

Retries are only attempted for normalized `AttractorEx.LLM.Error` values marked as
retryable, or when a custom `retry_if` callback explicitly opts in.

# `retry_if`

```elixir
@type retry_if() :: (AttractorEx.LLM.Error.t(), pos_integer() -&gt; boolean())
```

# `t`

```elixir
@type t() :: %AttractorEx.LLM.RetryPolicy{
  base_delay_ms: non_neg_integer(),
  jitter_ratio: float(),
  max_attempts: pos_integer(),
  max_delay_ms: non_neg_integer(),
  retry_if: retry_if() | nil
}
```

# `delay_ms`

```elixir
@spec delay_ms(t(), AttractorEx.LLM.Error.t(), pos_integer()) :: non_neg_integer()
```

# `enabled?`

```elixir
@spec enabled?(t() | nil) :: boolean()
```

# `new`

```elixir
@spec new(keyword() | map() | nil) :: t() | nil
```

# `retry?`

```elixir
@spec retry?(t(), AttractorEx.LLM.Error.t(), pos_integer()) :: boolean()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
