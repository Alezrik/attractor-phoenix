# `AttractorEx.Agent.BuiltinTools`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/agent/builtin_tools.ex#L1)

Built-in coding-agent tools backed by an `ExecutionEnvironment`.

These tools provide a provider-neutral baseline toolset that can be attached
to provider profiles such as OpenAI, Anthropic, and Gemini. Filesystem and
shell tools run against the execution environment, while subagent tools are
session-managed and operate on child `AttractorEx.Agent.Session` instances.

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
