defmodule AttractorEx.Handlers.Default do
  @moduledoc false

  alias AttractorEx.Outcome

  def execute(node, _context, _graph, _stage_dir, _opts) do
    Outcome.fail("No handler found for node type `#{node.type}`.")
  end
end
