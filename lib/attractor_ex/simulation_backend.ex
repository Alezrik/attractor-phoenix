defmodule AttractorEx.SimulationBackend do
  @moduledoc false

  def run(node, prompt, _context) do
    "Simulated response for #{node.id}: #{prompt}"
  end
end
