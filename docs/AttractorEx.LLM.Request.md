# `AttractorEx.LLM.Request`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/llm/request.ex#L1)

Unified request struct for provider-agnostic LLM completions.

The data model is intentionally small and focuses on the fields currently required by
codergen nodes and the agent session layer.

# `t`

```elixir
@type t() :: %AttractorEx.LLM.Request{
  cache: map() | nil,
  max_tokens: integer() | nil,
  messages: [AttractorEx.LLM.Message.t()],
  metadata: map(),
  model: String.t() | nil,
  provider: String.t() | nil,
  provider_options: map(),
  reasoning_effort: String.t(),
  response_format: :text | :json | %{type: :json_schema, schema: map()} | nil,
  retry_policy: keyword() | map() | nil,
  stop_sequences: [String.t()],
  temperature: float() | nil,
  tool_choice: String.t() | map() | nil,
  tools: list(),
  top_p: float() | nil
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
