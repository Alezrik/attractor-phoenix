# `AttractorEx.LLM.Usage`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/llm/usage.ex#L1)

Normalized token-usage counters returned by LLM responses and streams.

# `t`

```elixir
@type t() :: %AttractorEx.LLM.Usage{
  cache_read_tokens: non_neg_integer(),
  cache_write_tokens: non_neg_integer(),
  input_tokens: non_neg_integer(),
  output_tokens: non_neg_integer(),
  reasoning_tokens: non_neg_integer(),
  total_tokens: non_neg_integer()
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
