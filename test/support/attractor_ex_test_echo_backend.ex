defmodule AttractorExTest.EchoBackend do
  @moduledoc false

  def run(node, prompt, _context) do
    "echo:#{node.id}:#{prompt}"
  end
end
