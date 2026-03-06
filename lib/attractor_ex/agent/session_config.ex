defmodule AttractorEx.Agent.SessionConfig do
  @moduledoc false

  @default_tool_output_limits %{
    "read_file" => 50_000,
    "shell_command" => 30_000,
    "grep" => 20_000,
    "glob" => 20_000,
    "__default__" => 20_000
  }

  @default_tool_line_limits %{
    "shell_command" => 256,
    "grep" => 200,
    "glob" => 500
  }

  defstruct max_turns: 0,
            max_tool_rounds_per_input: 0,
            default_command_timeout_ms: 10_000,
            max_command_timeout_ms: 600_000,
            reasoning_effort: nil,
            tool_output_limits: @default_tool_output_limits,
            tool_output_line_limits: @default_tool_line_limits,
            enable_loop_detection: true,
            loop_detection_window: 10,
            max_subagent_depth: 1

  @type t :: %__MODULE__{
          max_turns: non_neg_integer(),
          max_tool_rounds_per_input: non_neg_integer(),
          default_command_timeout_ms: pos_integer(),
          max_command_timeout_ms: pos_integer(),
          reasoning_effort: String.t() | nil,
          tool_output_limits: %{optional(String.t()) => pos_integer()},
          tool_output_line_limits: %{optional(String.t()) => pos_integer()},
          enable_loop_detection: boolean(),
          loop_detection_window: pos_integer(),
          max_subagent_depth: non_neg_integer()
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct(__MODULE__, opts)
  end
end
