# `AttractorEx.Agent.Session`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/agent/session.ex#L1)

Stateful coding-agent loop built on top of `AttractorEx.LLM.Client`.

A session owns request construction, conversation history, tool execution, tool
result truncation, steering and follow-up queues, loop detection, subagent
lifecycle management, and lifecycle events.

# `state`

```elixir
@type state() :: :idle | :processing | :awaiting_input | :closed
```

# `t`

```elixir
@type t() :: %AttractorEx.Agent.Session{
  abort_signaled: boolean(),
  config: AttractorEx.Agent.SessionConfig.t(),
  depth: non_neg_integer(),
  events: [AttractorEx.Agent.Event.t()],
  execution_env: term(),
  followup_queue: :queue.queue(String.t()),
  history: [turn()],
  id: String.t(),
  llm_client: AttractorEx.LLM.Client.t(),
  provider_profile: AttractorEx.Agent.ProviderProfile.t(),
  state: state(),
  steering_queue: :queue.queue(String.t()),
  subagents: map()
}
```

# `turn`

```elixir
@type turn() ::
  %{type: :user, content: String.t(), timestamp: DateTime.t()}
  | %{
      type: :assistant,
      content: String.t(),
      tool_calls: list(),
      reasoning: String.t() | nil,
      usage: map(),
      response_id: String.t() | nil,
      timestamp: DateTime.t()
    }
  | %{
      type: :tool_results,
      results: [AttractorEx.Agent.ToolResult.t()],
      timestamp: DateTime.t()
    }
  | %{type: :steering, content: String.t(), timestamp: DateTime.t()}
  | %{type: :system, content: String.t(), timestamp: DateTime.t()}
```

# `abort`

```elixir
@spec abort(t()) :: t()
```

Marks the session as aborted and closed.

# `close`

```elixir
@spec close(t()) :: t()
```

Closes the session without aborting an in-flight tool.

# `follow_up`

```elixir
@spec follow_up(t(), String.t()) :: t()
```

Queues a follow-up user input to run after the current submission completes.

# `new`

```elixir
@spec new(
  AttractorEx.LLM.Client.t(),
  AttractorEx.Agent.ProviderProfile.t(),
  keyword()
) :: t()
```

Builds a new coding-agent session.

# `run_subagent_tool`

```elixir
@spec run_subagent_tool(t(), String.t(), map()) ::
  {String.t() | map() | list() | term(), t()} | no_return()
```

Executes a session-managed subagent tool and returns `{output, updated_session}`.

# `steer`

```elixir
@spec steer(t(), String.t()) :: t()
```

Queues steering text to be injected on the next round.

# `submit`

```elixir
@spec submit(t(), String.t()) :: t()
```

Submits a user message into the agent loop.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
