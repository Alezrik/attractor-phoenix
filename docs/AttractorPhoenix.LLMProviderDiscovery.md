# `AttractorPhoenix.LLMProviderDiscovery`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_phoenix/llm_provider_discovery.ex#L1)

Fetches available models for supported providers using provider-native model listing APIs.

# `model`

```elixir
@type model() :: %{
  id: String.t(),
  provider: String.t(),
  label: String.t(),
  raw: map()
}
```

# `fetch_models`

```elixir
@spec fetch_models(String.t(), String.t()) :: {:ok, [model()]} | {:error, String.t()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
