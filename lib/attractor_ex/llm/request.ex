defmodule AttractorEx.LLM.Request do
  @moduledoc """
  Unified request struct for provider-agnostic LLM completions.

  The data model is intentionally small and focuses on the fields currently required by
  codergen nodes and the agent session layer.
  """

  alias AttractorEx.LLM.Message

  defstruct model: nil,
            provider: nil,
            messages: [],
            max_tokens: nil,
            temperature: nil,
            top_p: nil,
            stop_sequences: [],
            reasoning_effort: "high",
            tools: [],
            tool_choice: nil,
            response_format: nil,
            cache: nil,
            retry_policy: nil,
            provider_options: %{},
            metadata: %{}

  @type t :: %__MODULE__{
          model: String.t() | nil,
          provider: String.t() | nil,
          messages: [Message.t()],
          max_tokens: integer() | nil,
          temperature: float() | nil,
          top_p: float() | nil,
          stop_sequences: [String.t()],
          reasoning_effort: String.t(),
          tools: list(),
          tool_choice: String.t() | map() | nil,
          response_format: :text | :json | %{type: :json_schema, schema: map()} | nil,
          cache: map() | nil,
          retry_policy: keyword() | map() | nil,
          provider_options: map(),
          metadata: map()
        }
end
