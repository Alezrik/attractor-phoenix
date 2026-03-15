# `AttractorEx.LLM.ObjectStream`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/llm/object_stream.ex#L1)

Incremental JSON object streaming helpers for normalized LLM event streams.

The transformer understands two practical patterns:

1. newline-delimited JSON (`NDJSON`) values emitted in text deltas
2. full JSON documents that become valid as the accumulated text grows

# `state`

```elixir
@type state() :: %{
  line_buffer: String.t(),
  document_buffer: String.t(),
  last_document_hash: integer() | nil
}
```

# `insert_object_events`

```elixir
@spec insert_object_events(Enumerable.t()) :: Enumerable.t()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
