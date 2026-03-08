# `AttractorEx.LLM.MessagePart`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/llm/message_part.ex#L1)

Tagged content part used by `AttractorEx.LLM.Message`.

The unified client still treats multimodal payloads as pass-through data for provider
adapters, but this struct gives requests a stable representation for richer content.

# `part_type`

```elixir
@type part_type() ::
  :text
  | :image
  | :audio
  | :document
  | :tool_call
  | :tool_result
  | :thinking
  | :json
```

Known content part kinds carried by the normalized message model.

# `t`

```elixir
@type t() :: %AttractorEx.LLM.MessagePart{
  data: map(),
  mime_type: String.t() | nil,
  text: String.t() | nil,
  type: part_type()
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
