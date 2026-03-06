defmodule AttractorEx.Handlers.Parallel do
  @moduledoc false

  alias AttractorEx.Edge
  alias AttractorEx.Outcome

  def execute(node, context, graph, _stage_dir, opts) do
    branches =
      graph.edges
      |> Enum.filter(&(&1.from == node.id))

    if branches == [] do
      Outcome.fail("No outgoing branches for parallel node")
    else
      join_policy = node.attrs["join_policy"] || "wait_all"
      max_parallel = parse_int(node.attrs["max_parallel"], 4)
      runner = Keyword.get(opts, :parallel_branch_runner, &default_runner/4)

      results =
        branches
        |> Task.async_stream(
          fn %Edge{to: to, attrs: attrs} ->
            branch_context = :erlang.binary_to_term(:erlang.term_to_binary(context))
            branch_result = normalize_branch_result(runner.(to, branch_context, graph, opts))
            %{id: to, edge_attrs: attrs, outcome: branch_result}
          end,
          max_concurrency: max_parallel,
          timeout: :infinity
        )
        |> Enum.map(fn
          {:ok, result} ->
            result

          {:exit, reason} ->
            %{id: "unknown", edge_attrs: %{}, outcome: Outcome.fail(inspect(reason))}
        end)

      success_count = Enum.count(results, &(&1.outcome.status == :success))
      fail_count = Enum.count(results, &(&1.outcome.status == :fail))

      status =
        case join_policy do
          "first_success" ->
            if success_count > 0, do: :success, else: :fail

          "k_of_n" ->
            k = parse_int(node.attrs["k"], 1)
            if success_count >= k, do: :success, else: :partial_success

          "quorum" ->
            quorum_ratio = parse_float(node.attrs["quorum_ratio"], 0.5)

            if success_count / max(1, length(results)) >= quorum_ratio,
              do: :success,
              else: :partial_success

          _ ->
            if fail_count == 0, do: :success, else: :partial_success
        end

      updates = %{"parallel.results" => Enum.map(results, &serialize_result/1)}

      case status do
        :success ->
          Outcome.success(updates, "Parallel completed: #{node.id}")

        :partial_success ->
          Outcome.partial_success(updates, "Parallel partially completed: #{node.id}")

        :fail ->
          Outcome.fail("Parallel failed: #{node.id}")
      end
    end
  end

  defp normalize_branch_result(%Outcome{} = result), do: result

  defp normalize_branch_result(other),
    do: Outcome.success(%{"result" => inspect(other)}, "branch success")

  defp serialize_result(result) do
    %{
      "id" => result.id,
      "status" => result.outcome.status,
      "notes" => result.outcome.notes,
      "failure_reason" => result.outcome.failure_reason,
      "score" => parse_float(result.edge_attrs["score"], 0.0)
    }
  end

  defp parse_int(nil, default), do: default
  defp parse_int(value, _default) when is_integer(value), do: value

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> parsed
      _ -> default
    end
  end

  defp parse_int(_, default), do: default

  defp parse_float(nil, default), do: default
  defp parse_float(value, _default) when is_float(value), do: value
  defp parse_float(value, _default) when is_integer(value), do: value * 1.0

  defp parse_float(value, default) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {parsed, ""} -> parsed
      _ -> default
    end
  end

  defp parse_float(_, default), do: default

  defp default_runner(_to, _context, _graph, _opts), do: Outcome.success(%{}, "branch success")
end
