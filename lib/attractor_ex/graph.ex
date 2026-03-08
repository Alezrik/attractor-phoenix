defmodule AttractorEx.Graph do
  @moduledoc """
  Normalized in-memory representation of a parsed pipeline graph.

  A graph carries graph-level attributes, node and edge defaults, a node map, and a
  flat edge list. `AttractorEx.Parser` produces this struct, `AttractorEx.Validator`
  checks it, and `AttractorEx.Engine` executes it.
  """

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
