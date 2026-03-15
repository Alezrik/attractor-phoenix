# `AttractorPhoenix.LLMAdapters.HTTP`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_phoenix/llm_adapters/http.ex#L1)

Shared HTTP helpers for native LLM provider adapters.

# `post_json`

```elixir
@spec post_json(String.t(), [{String.t(), String.t()}], map(), keyword()) ::
  {:ok, map()} | {:error, AttractorEx.LLM.Error.t()}
```

# `post_json_stream`

```elixir
@spec post_json_stream(String.t(), [{String.t(), String.t()}], map(), keyword()) ::
  {:ok, %{body: String.t(), headers: map(), status: pos_integer()}}
  | {:error, AttractorEx.LLM.Error.t()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
