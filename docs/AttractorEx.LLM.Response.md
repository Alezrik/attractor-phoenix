# `AttractorEx.LLM.Response`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/llm/response.ex#L1)

Unified response struct returned by provider adapters.

# `t`

```elixir
@type t() :: %AttractorEx.LLM.Response{
  finish_reason: String.t(),
  id: String.t() | nil,
  raw: map(),
  reasoning: String.t() | nil,
  text: String.t(),
  tool_calls: list(),
  usage: AttractorEx.LLM.Usage.t()
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
