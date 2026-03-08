defmodule AttractorEx.Handler do
  @moduledoc """
  Behaviour implemented by all executable node handlers.

  Handlers receive the normalized node, current context, full graph, stage directory,
  and runtime options, and must return an `AttractorEx.Outcome`.
  """

  alias AttractorEx.{Graph, Node, Outcome}

  @callback execute(Node.t(), map(), Graph.t(), String.t(), keyword()) :: Outcome.t()
end
