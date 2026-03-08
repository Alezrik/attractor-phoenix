# `AttractorEx.LLM.Message`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/llm/message.ex#L1)

Unified chat message struct used in LLM requests.

`content` remains backward compatible with plain strings, but can also carry a list
of tagged content parts through `AttractorEx.LLM.MessagePart`.

# `content`

```elixir
@type content() :: String.t() | [AttractorEx.LLM.MessagePart.t()]
```

# `role`

```elixir
@type role() :: :system | :user | :assistant | :tool | :developer
```

# `t`

```elixir
@type t() :: %AttractorEx.LLM.Message{
  content: content(),
  metadata: map(),
  name: String.t() | nil,
  role: role(),
  tool_call_id: String.t() | nil
}
```

# `content_text`

```elixir
@spec content_text(content()) :: String.t()
```

Returns the plain-text projection of a message content payload.

Text and thinking parts contribute their text directly. Tool, image, audio, document,
and JSON parts are summarized into a stable textual marker for callers that still need
a rough size estimate or fallback prompt representation.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
