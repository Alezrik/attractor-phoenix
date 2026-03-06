defmodule AttractorExTest.SuggestedNextBackend do
  @moduledoc false

  alias AttractorEx.Outcome

  def run(node, _prompt, _context) do
    if node.id == "router" do
      %Outcome{status: :success, suggested_next_ids: ["path_b"], context_updates: %{}}
    else
      Outcome.success()
    end
  end
end
