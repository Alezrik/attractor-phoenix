defmodule AttractorEx.Handlers.Conditional do
  @moduledoc false

  alias AttractorEx.Outcome

  def execute(node, _context, _graph, _stage_dir, _opts) do
    Outcome.success(%{}, "Conditional node evaluated: #{node.id}")
  end
end
