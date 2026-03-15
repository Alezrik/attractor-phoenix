defmodule AttractorEx.HTTP.CheckpointRecord do
  @moduledoc """
  Typed checkpoint snapshot persisted by the HTTP runtime manager.
  """

  @enforce_keys [:current_node, :completed_nodes, :context, :timestamp]
  defstruct [:current_node, :completed_nodes, :context, :timestamp]

  @type t :: %__MODULE__{
          current_node: String.t() | nil,
          completed_nodes: [String.t()],
          context: map(),
          timestamp: String.t()
        }

  @spec from_map(map()) :: t()
  def from_map(checkpoint) when is_map(checkpoint) do
    %__MODULE__{
      current_node: Map.get(checkpoint, "current_node") || Map.get(checkpoint, :current_node),
      completed_nodes:
        Map.get(checkpoint, "completed_nodes") || Map.get(checkpoint, :completed_nodes) || [],
      context: Map.get(checkpoint, "context") || Map.get(checkpoint, :context) || %{},
      timestamp:
        Map.get(checkpoint, "timestamp") || Map.get(checkpoint, :timestamp) || now_iso8601()
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = checkpoint) do
    %{
      "current_node" => checkpoint.current_node,
      "completed_nodes" => checkpoint.completed_nodes,
      "context" => checkpoint.context,
      "timestamp" => checkpoint.timestamp
    }
  end

  defp now_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
