defmodule AttractorExTest.FlakyGoalGateBackend do
  @moduledoc false

  alias AttractorEx.Outcome

  def run(node, _prompt, context) do
    attempts =
      context
      |> Map.get("goal_gate_attempts", 0)

    if node.id == "implement" and attempts == 0 do
      %Outcome{
        status: :fail,
        notes: "first attempt fails",
        context_updates: %{"goal_gate_attempts" => 1}
      }
    else
      Outcome.success(
        %{"goal_gate_attempts" => attempts + 1, "backend" => %{node.id => "ok"}},
        "attempt succeeded"
      )
    end
  end
end
