defmodule AttractorEx.LLM.Message do
  @moduledoc false

  defstruct role: :user, content: ""

  @type role :: :system | :user | :assistant | :tool | :developer
  @type t :: %__MODULE__{role: role(), content: String.t()}
end
