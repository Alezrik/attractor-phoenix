defmodule AttractorEx.LLM.Message do
  @moduledoc """
  Minimal chat message struct used in unified LLM requests.
  """

  defstruct role: :user, content: ""

  @type role :: :system | :user | :assistant | :tool | :developer
  @type t :: %__MODULE__{role: role(), content: String.t()}
end
