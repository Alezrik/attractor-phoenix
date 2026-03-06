defmodule AttractorEx.Agent.ToolResult do
  @moduledoc false

  defstruct tool_call_id: nil, content: "", is_error: false

  @type t :: %__MODULE__{
          tool_call_id: String.t() | nil,
          content: String.t(),
          is_error: boolean()
        }
end
