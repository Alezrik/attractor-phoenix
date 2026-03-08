defmodule AttractorEx.Handlers.Conditional do
  @moduledoc """
  Handler for explicit conditional nodes.

  The node itself succeeds immediately. Branch selection happens later when the engine
  evaluates outgoing edge conditions.
  """

  alias AttractorEx.Outcome

  def execute(node, _context, _graph, _stage_dir, _opts) do
    Outcome.success(%{}, "Conditional node evaluated: #{node.id}")
  end
end
