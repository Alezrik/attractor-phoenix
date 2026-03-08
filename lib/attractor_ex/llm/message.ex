defmodule AttractorEx.LLM.Message do
  @moduledoc """
  Unified chat message struct used in LLM requests.

  `content` remains backward compatible with plain strings, but can also carry a list
  of tagged content parts through `AttractorEx.LLM.MessagePart`.
  """

  alias AttractorEx.LLM.MessagePart

  defstruct role: :user, content: "", name: nil, tool_call_id: nil, metadata: %{}

  @type role :: :system | :user | :assistant | :tool | :developer
  @type content :: String.t() | [MessagePart.t()]

  @type t :: %__MODULE__{
          role: role(),
          content: content(),
          name: String.t() | nil,
          tool_call_id: String.t() | nil,
          metadata: map()
        }

  @doc """
  Returns the plain-text projection of a message content payload.

  Text and thinking parts contribute their text directly. Tool, image, audio, document,
  and JSON parts are summarized into a stable textual marker for callers that still need
  a rough size estimate or fallback prompt representation.
  """
  @spec content_text(content()) :: String.t()
  def content_text(content) when is_binary(content), do: content

  def content_text(content) when is_list(content) do
    content
    |> Enum.map_join("", &MessagePart.text_projection/1)
    |> String.trim()
  end

  def content_text(_content), do: ""
end
