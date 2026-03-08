defmodule AttractorEx.Agent.Event do
  @moduledoc """
  Typed session event emitted by `AttractorEx.Agent.Session`.

  The shape mirrors the coding-agent loop spec's session-event contract while
  keeping a `payload` alias for backward compatibility with older callers.
  """

  @type kind ::
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

  defstruct kind: :session_start,
            timestamp: nil,
            session_id: nil,
            data: %{},
            payload: %{}

  @type t :: %__MODULE__{
          kind: kind(),
          timestamp: DateTime.t(),
          session_id: String.t(),
          data: map(),
          payload: map()
        }

  @spec new(kind(), String.t(), map(), DateTime.t()) :: t()
  def new(kind, session_id, data, timestamp \\ DateTime.utc_now())
      when is_atom(kind) and is_binary(session_id) and is_map(data) do
    %__MODULE__{
      kind: kind,
      timestamp: timestamp,
      session_id: session_id,
      data: data,
      payload: data
    }
  end

  @spec supported_kinds() :: [kind()]
  def supported_kinds do
    [
      :session_start,
      :session_end,
      :user_input,
      :assistant_text_start,
      :assistant_text_delta,
      :assistant_text_end,
      :tool_call_start,
      :tool_call_output_delta,
      :tool_call_end,
      :steering_injected,
      :turn_limit,
      :loop_detection,
      :error
    ]
  end
end
