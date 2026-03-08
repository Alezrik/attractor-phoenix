defmodule AttractorEx.SimulationBackend do
  @moduledoc """
  Minimal fallback backend used by `AttractorEx.Handlers.Codergen` in tests and demos.
  """

  def run(node, prompt, _context) do
    "Simulated response for #{node.id}: #{prompt}"
  end
end
