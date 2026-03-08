# `AttractorEx.Agent.Event`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/agent/event.ex#L1)

Typed session event emitted by `AttractorEx.Agent.Session`.

The shape mirrors the coding-agent loop spec's session-event contract while
keeping a `payload` alias for backward compatibility with older callers.

# `kind`

```elixir
@type kind() ::
  :session_start
  | :session_end
  | :user_input
  | :assistant_text_start
  | :assistant_text_delta
  | :assistant_text_end
  | :tool_call_start
  | :tool_call_output_delta
  | :tool_call_end
  | :steering_injected
  | :turn_limit
  | :loop_detection
  | :context_warning
  | :subagent_spawned
  | :subagent_input_sent
  | :subagent_wait_completed
  | :subagent_closed
  | :error
```

# `t`

```elixir
@type t() :: %AttractorEx.Agent.Event{
  data: map(),
  kind: kind(),
  payload: map(),
  session_id: String.t(),
  timestamp: DateTime.t()
}
```

# `new`

```elixir
@spec new(kind(), String.t(), map(), DateTime.t()) :: t()
```

# `supported_kinds`

```elixir
@spec supported_kinds() :: [kind()]
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
