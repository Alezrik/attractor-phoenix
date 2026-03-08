# `AttractorEx.Agent.SessionConfig`
[🔗](https://github.com/Alezrik/attractor-phoenix/blob/main/lib/attractor_ex/agent/session_config.ex#L1)

Runtime configuration for coding-agent sessions.

This struct centralizes turn limits, tool-round limits, timeout policy, output
truncation policy, and loop-detection settings.

# `t`

```elixir
@type t() :: %AttractorEx.Agent.SessionConfig{
  default_command_timeout_ms: pos_integer(),
  enable_loop_detection: boolean(),
  loop_detection_window: pos_integer(),
  max_command_timeout_ms: pos_integer(),
  max_subagent_depth: non_neg_integer(),
  max_tool_rounds_per_input: non_neg_integer(),
  max_turns: non_neg_integer(),
  reasoning_effort: String.t() | nil,
  tool_output_limits: %{optional(String.t()) =&gt; pos_integer()},
  tool_output_line_limits: %{optional(String.t()) =&gt; pos_integer()}
}
```

# `new`

```elixir
@spec new(keyword()) :: t()
```

Builds a session config, merging tool output limit overrides with defaults.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
