# `AttractorEx.LLM.StreamEvent`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/llm/stream_event.ex#L1)

Event struct used by streaming LLM adapters.

Events cover stream lifecycle markers, text and reasoning deltas, tool payloads, the
final response, and error cases.

# `event_type`

```elixir
@type event_type() ::
  :stream_start
  | :text_delta
  | :reasoning_delta
  | :tool_call
  | :tool_result
  | :response
  | :stream_end
  | :error
```

# `t`

```elixir
@type t() :: %AttractorEx.LLM.StreamEvent{
  error: term() | nil,
  raw: map(),
  reasoning: String.t() | nil,
  response: AttractorEx.LLM.Response.t() | nil,
  text: String.t() | nil,
  tool_call: map() | nil,
  tool_result: map() | nil,
  type: event_type() | String.t(),
  usage: AttractorEx.LLM.Usage.t() | nil
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
