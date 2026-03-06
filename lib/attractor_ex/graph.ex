defmodule AttractorEx.Graph do
  @moduledoc false

  @type t :: %__MODULE__{
          id: String.t(),
          attrs: map(),
          node_defaults: map(),
          edge_defaults: map(),
          nodes: map(),
          edges: list()
        }

  defstruct id: "pipeline",
            attrs: %{},
            node_defaults: %{},
            edge_defaults: %{},
            nodes: %{},
            edges: []
end
