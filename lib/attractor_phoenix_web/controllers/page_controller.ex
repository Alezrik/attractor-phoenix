defmodule AttractorPhoenixWeb.PageController do
  use AttractorPhoenixWeb, :controller

  def home(conn, _params) do
    render(conn, :home,
      dot: sample_dot(),
      context_json: "{}",
      result: nil,
      error: nil
    )
  end

  def run(conn, %{"pipeline" => %{"dot" => dot, "context_json" => context_json}}) do
    with {:ok, context} <- decode_context(context_json),
         {:ok, result} <- AttractorExPhx.run(dot, context, logs_root: "tmp/runs") do
      render(conn, :home, dot: dot, context_json: context_json, result: result, error: nil)
    else
      {:error, %{diagnostics: diagnostics}} ->
        render(conn, :home,
          dot: dot,
          context_json: context_json,
          result: nil,
          error: "Validation failed: #{Jason.encode_to_iodata!(diagnostics)}"
        )

      {:error, %{error: message}} ->
        render(conn, :home, dot: dot, context_json: context_json, result: nil, error: message)

      {:error, message} ->
        render(conn, :home,
          dot: dot,
          context_json: context_json,
          result: nil,
          error: to_string(message)
        )
    end
  end

  def run(conn, _params) do
    render(conn, :home,
      dot: sample_dot(),
      context_json: "{}",
      result: nil,
      error: "Invalid submission payload."
    )
  end

  defp decode_context(context_json) when is_binary(context_json) do
    case Jason.decode(context_json) do
      {:ok, context} when is_map(context) -> {:ok, context}
      {:ok, _} -> {:error, "Context JSON must be an object."}
      {:error, error} -> {:error, "Context JSON is invalid: #{Exception.message(error)}"}
    end
  end

  defp sample_dot do
    """
    digraph attractor {
      graph [goal="Implement and validate a feature"]
      start [shape=Mdiamond]
      plan [shape=box, prompt="Create a plan for $goal"]
      implement [shape=box, prompt="Implement according to plan", goal_gate=true]
      review [shape=box, prompt="Review implementation quality"]
      done [shape=Msquare]

      start -> plan
      plan -> implement
      implement -> review
      review -> done
    }
    """
  end
end
