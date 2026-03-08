defmodule AttractorEx.Agent.ToolCall do
  @moduledoc """
  Normalized representation of a tool call requested by the model.
  """

  defstruct id: nil, name: "", arguments: %{}

  @type t :: %__MODULE__{
          id: String.t() | nil,
          name: String.t(),
          arguments: map() | String.t()
        }
end
