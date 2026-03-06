defmodule AttractorEx.Agent.ToolCall do
  @moduledoc false

  defstruct id: nil, name: "", arguments: %{}

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t(),
          arguments: map() | String.t()
        }
end
