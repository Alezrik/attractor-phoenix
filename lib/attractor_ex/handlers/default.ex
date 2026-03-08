defmodule AttractorEx.Handlers.Default do
  @moduledoc """
  Fallback handler used when a node type does not need special runtime behavior.
  """

  alias AttractorEx.Outcome

  def execute(node, _context, _graph, _stage_dir, _opts) do
    Outcome.fail("No handler found for node type `#{node.type}`.")
  end
end
