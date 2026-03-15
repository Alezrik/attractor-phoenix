defmodule AttractorEx.LLM.StreamEvent do
  @moduledoc """
  Event struct used by streaming LLM adapters.

  Events cover stream lifecycle markers, text and reasoning deltas, tool payloads, the
  final response, and error cases.
  """

  alias AttractorEx.LLM.{Response, Usage}

  @type event_type ::
          :stream_start
          | :text_delta
          | :reasoning_delta
          | :object_delta
          | :tool_call
          | :tool_result
          | :response
          | :stream_end
          | :error

  defstruct type: :stream_start,
            text: nil,
            reasoning: nil,
            object: nil,
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
          object: map() | list() | nil,
          tool_call: map() | nil,
          tool_result: map() | nil,
          usage: Usage.t() | nil,
          response: Response.t() | nil,
          raw: map(),
          error: term() | nil
        }
end
