# `AttractorEx.Agent.ProviderProfile`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/agent/provider_profile.ex#L1)

Provider-aligned configuration for the coding-agent loop.

A profile packages a model, toolset, provider options, and an optional system-prompt
builder so agent sessions can stay portable across providers.

The module also exposes a maintained cross-provider integration matrix for the
built-in OpenAI, Anthropic, and Gemini presets.

# `integration_entry`

```elixir
@type integration_entry() :: %{
  id: String.t(),
  provider_family: atom(),
  preset: atom(),
  implemented_tool_names: [String.t()],
  reference_tool_names: [String.t()],
  instruction_files: [String.t()],
  reasoning_option_path: [String.t()],
  system_prompt_style: String.t(),
  event_kinds: [AttractorEx.Agent.Event.kind()]
}
```

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

# `instruction_files`

```elixir
@spec instruction_files(t()) :: [String.t()]
```

Returns the project-instruction files relevant to the active provider profile.

# `integration_matrix`

```elixir
@spec integration_matrix() :: [integration_entry()]
```

Returns the maintained cross-provider integration matrix for built-in presets.

# `new`

```elixir
@spec new(keyword()) :: t()
```

Builds a provider profile from keyword options.

# `openai`

```elixir
@spec openai(keyword()) :: t()
```

# `reasoning_option_path`

```elixir
@spec reasoning_option_path(t()) :: [String.t()]
```

Returns the provider-native request path associated with reasoning/thinking controls.

# `reference_tool_names`

```elixir
@spec reference_tool_names(t()) :: [String.t()]
```

Returns the upstream native tool names the preset is intended to align with.

# `system_prompt_style`

```elixir
@spec system_prompt_style(t()) :: String.t()
```

Returns the reference-agent prompt family used as the preset target.

# `tool_definitions`

```elixir
@spec tool_definitions(t()) :: [map()]
```

Returns the serialized tool definitions exposed to the model.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
