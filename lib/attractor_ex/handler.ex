defmodule AttractorEx.Handler do
  @moduledoc false

  alias AttractorEx.{Graph, Node, Outcome}

  @callback execute(Node.t(), map(), Graph.t(), String.t(), keyword()) :: Outcome.t()
end
