defmodule AttractorExTest.FailBackend do
  @moduledoc false

  alias AttractorEx.Outcome

  def run(node, _prompt, _context) do
    if node.id == "task" do
      Outcome.fail("task failed")
    else
      Outcome.success()
    end
  end
end
