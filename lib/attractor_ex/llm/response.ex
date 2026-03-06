defmodule AttractorEx.LLM.Response do
  @moduledoc false

  alias AttractorEx.LLM.Usage

  defstruct text: "",
            tool_calls: [],
            reasoning: nil,
            usage: %Usage{},
            finish_reason: "stop",
            id: nil,
            raw: %{}

  @type t :: %__MODULE__{
          text: String.t(),
          tool_calls: list(),
          reasoning: String.t() | nil,
          usage: Usage.t(),
          finish_reason: String.t(),
          id: String.t() | nil,
          raw: map()
        }
end
