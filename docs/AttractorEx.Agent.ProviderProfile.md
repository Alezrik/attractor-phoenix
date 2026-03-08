# `AttractorEx.Agent.ProviderProfile`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/agent/provider_profile.ex#L1)

Provider-aligned configuration for the coding-agent loop.

A profile packages a model, toolset, provider options, and an optional system-prompt
builder so agent sessions can stay portable across providers.

# `t`

```elixir
@type t() :: %AttractorEx.Agent.ProviderProfile{
  context_window_size: pos_integer() | nil,
  id: String.t(),
  model: String.t(),
  preset: atom() | nil,
  provider_family: atom(),
  provider_options: map(),
  supports_parallel_tool_calls: boolean(),
  system_prompt_builder: (keyword() -&gt; String.t()) | nil,
  tool_registry: AttractorEx.Agent.ToolRegistry.t(),
  tools: [AttractorEx.Agent.Tool.t()]
}
```

# `anthropic`

```elixir
@spec anthropic(keyword()) :: t()
```

# `build_system_prompt`

```elixir
@spec build_system_prompt(
  t(),
  keyword()
) :: String.t()
```

Builds the system prompt for a session request.

# `gemini`

```elixir
@spec gemini(keyword()) :: t()
```

# `new`

```elixir
@spec new(keyword()) :: t()
```

Builds a provider profile from keyword options.

# `openai`

```elixir
@spec openai(keyword()) :: t()
```

# `tool_definitions`

```elixir
@spec tool_definitions(t()) :: [map()]
```

Returns the serialized tool definitions exposed to the model.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
