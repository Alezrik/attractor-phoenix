defmodule AttractorEx.Checkpoint do
  @moduledoc """
  Serializable checkpoint snapshot for resumable pipeline execution.

  The engine writes checkpoints after every stage and accepts them again through
  `AttractorEx.resume/3`.
  """

  defstruct timestamp: nil, current_node: nil, completed_nodes: [], context: %{}

  @doc "Builds a checkpoint using the current UTC timestamp."
  def new(current_node, completed_nodes, context) do
    %__MODULE__{
      timestamp: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      current_node: current_node,
      completed_nodes: completed_nodes,
      context: context
    }
  end
end
