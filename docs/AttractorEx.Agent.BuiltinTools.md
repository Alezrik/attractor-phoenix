# `AttractorEx.Agent.BuiltinTools`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/agent/builtin_tools.ex#L1)

Built-in coding-agent tools backed by an `ExecutionEnvironment`.

The `:default` preset exposes a provider-neutral baseline toolset. Provider
presets then layer provider-native tool names and argument shapes on top of
the same execution environment so OpenAI, Anthropic, and Gemini sessions can
stay closer to their upstream agent harnesses.

# `preset`

```elixir
@type preset() :: :openai | :anthropic | :gemini | :default
```

# `for_provider`

```elixir
@spec for_provider(preset()) :: [AttractorEx.Agent.Tool.t()]
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
