defmodule AttractorExTest.PreferredLabelBackend do
  @moduledoc false

  alias AttractorEx.Outcome

  def run(node, _prompt, _context) do
    if node.id == "router" do
      %Outcome{status: :success, preferred_label: "[Y] Ship It", context_updates: %{}}
    else
      Outcome.success()
    end
  end
end
