defmodule AttractorEx.Checkpoint do
  @moduledoc false

  defstruct timestamp: nil, current_node: nil, completed_nodes: [], context: %{}

  def new(current_node, completed_nodes, context) do
    %__MODULE__{
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      current_node: current_node,
      completed_nodes: completed_nodes,
      context: context
    }
  end
end
