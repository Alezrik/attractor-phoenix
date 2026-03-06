defmodule AttractorEx.Handlers.Exit do
  @moduledoc false

  alias AttractorEx.Outcome

  def execute(_node, _context, _graph, _stage_dir, _opts), do: Outcome.success()
end
