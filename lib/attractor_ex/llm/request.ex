defmodule AttractorEx.LLM.Request do
  @moduledoc false

  alias AttractorEx.LLM.Message

  defstruct model: nil,
            provider: nil,
            messages: [],
            max_tokens: nil,
            temperature: nil,
            reasoning_effort: "high",
            tools: [],
            tool_choice: nil,
            provider_options: %{},
            metadata: %{}

  @type t :: %__MODULE__{
          model: String.t() | nil,
          provider: String.t() | nil,
          messages: [Message.t()],
          max_tokens: integer() | nil,
          temperature: float() | nil,
          reasoning_effort: String.t(),
          tools: list(),
          tool_choice: String.t() | map() | nil,
          provider_options: map(),
          metadata: map()
        }
end
