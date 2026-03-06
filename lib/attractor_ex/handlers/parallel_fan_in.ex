defmodule AttractorEx.Handlers.ParallelFanIn do
  @moduledoc false

  alias AttractorEx.Outcome

  def execute(node, context, _graph, _stage_dir, opts) do
    results = context["parallel.results"] || []

    if results == [] do
      Outcome.fail("No parallel results to evaluate")
    else
      best =
        if is_binary(node.prompt) and String.trim(node.prompt) != "" do
          evaluator = Keyword.get(opts, :fan_in_evaluator, &heuristic_select/1)
          evaluator.(results)
        else
          heuristic_select(results)
        end

      best_id = best["id"] || best[:id] || ""
      best_outcome = best["status"] || best[:status] || "success"

      Outcome.success(
        %{
          "parallel.fan_in.best_id" => to_string(best_id),
          "parallel.fan_in.best_outcome" => to_string(best_outcome)
        },
        "Selected best candidate: #{best_id}"
      )
    end
  end

  defp heuristic_select(candidates) do
    Enum.min_by(candidates, fn candidate ->
      status = candidate["status"] || candidate[:status] || :fail
      score = candidate["score"] || candidate[:score] || 0
      id = candidate["id"] || candidate[:id] || ""
      {outcome_rank(status), -score, to_string(id)}
    end)
  end

  defp outcome_rank(status) when is_atom(status), do: outcome_rank(Atom.to_string(status))

  defp outcome_rank(status) when is_binary(status) do
    case String.downcase(status) do
      "success" -> 0
      "partial_success" -> 1
      "retry" -> 2
      _ -> 3
    end
  end
end
