# `AttractorEx.LLM.Message`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/llm/message.ex#L1)

Minimal chat message struct used in unified LLM requests.

# `role`

```elixir
@type role() :: :system | :user | :assistant | :tool | :developer
```

# `t`

```elixir
@type t() :: %AttractorEx.LLM.Message{content: String.t(), role: role()}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
