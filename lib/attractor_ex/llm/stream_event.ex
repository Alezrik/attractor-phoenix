defmodule AttractorEx.LLM.StreamEvent do
  @moduledoc false

  alias AttractorEx.LLM.{Response, Usage}

  @type event_type ::
          :stream_start
          | :text_delta
          | :reasoning_delta
          | :tool_call
          | :tool_result
          | :response
          | :stream_end
          | :error

  defstruct type: :stream_start,
            text: nil,
            reasoning: nil,
            tool_call: nil,
            tool_result: nil,
            usage: nil,
            response: nil,
            raw: %{},
            error: nil

  @type t :: %__MODULE__{
          type: event_type() | String.t(),
          text: String.t() | nil,
          reasoning: String.t() | nil,
          tool_call: map() | nil,
          tool_result: map() | nil,
          usage: Usage.t() | nil,
          response: Response.t() | nil,
          raw: map(),
          error: term() | nil
        }
end
