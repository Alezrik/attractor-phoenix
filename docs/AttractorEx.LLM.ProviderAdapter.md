# `AttractorEx.LLM.ProviderAdapter`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/llm/provider_adapter.ex#L1)

Behaviour implemented by unified LLM provider adapters.

Adapters translate a normalized `AttractorEx.LLM.Request` into a provider-native API
call and return a normalized `AttractorEx.LLM.Response` or stream of events.

# `complete`

```elixir
@callback complete(AttractorEx.LLM.Request.t()) ::
  AttractorEx.LLM.Response.t() | {:error, term()}
```

# `stream`
*optional* 

```elixir
@callback stream(AttractorEx.LLM.Request.t()) ::
  Enumerable.t(AttractorEx.LLM.StreamEvent.t()) | {:error, term()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
