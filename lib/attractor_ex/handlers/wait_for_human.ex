defmodule AttractorEx.Handlers.WaitForHuman do
  @moduledoc false

  alias AttractorEx.{Graph, Outcome}

  def execute(node, context, %Graph{} = graph, _stage_dir, _opts) do
    choices = choices_for(node.id, graph)

    cond do
      choices == [] ->
        Outcome.fail("No outgoing edges for human gate")

      true ->
        answer = human_answer(context, node.id)
        resolve_answer(node, answer, choices)
    end
  end

  def execute(node, context, _graph, _stage_dir, _opts) do
    execute(node, context, %Graph{}, nil, [])
  end

  defp resolve_answer(node, nil, _choices) do
    Outcome.retry("human gate requires answer in context.human.answers.#{node.id}")
  end

  defp resolve_answer(node, answer, choices) do
    normalized_answer = normalize_token(answer)

    cond do
      normalized_answer in ["timeout", "timed_out"] ->
        case node.attrs["human.default_choice"] do
          value when is_binary(value) and value != "" ->
            select_choice(value, choices) || Outcome.retry("human gate timeout, no valid default")

          _ ->
            Outcome.retry("human gate timeout, no default")
        end

      normalized_answer in ["skip", "skipped"] ->
        Outcome.fail("human skipped interaction")

      true ->
        select_choice(answer, choices) || select_choice(List.first(choices), choices)
    end
  end

  defp select_choice(nil, _choices), do: nil
  defp select_choice(%{} = choice, _choices), do: outcome_for_choice(choice)

  defp select_choice(value, choices) do
    normalized = normalize_token(value)

    Enum.find(choices, fn choice ->
      normalize_token(choice.key) == normalized or
        normalize_token(choice.label) == normalized or
        normalize_token(choice.to) == normalized
    end)
    |> case do
      nil -> nil
      choice -> outcome_for_choice(choice)
    end
  end

  defp outcome_for_choice(choice) do
    %Outcome{
      status: :success,
      suggested_next_ids: [choice.to],
      context_updates: %{
        "human" => %{
          "gate" => %{
            "selected" => choice.key,
            "label" => choice.label
          }
        }
      }
    }
  end

  defp human_answer(context, node_id) do
    get_in(context, ["human", "answers", node_id]) ||
      get_in(context, ["human", node_id, "answer"])
  end

  defp choices_for(node_id, graph) do
    graph.edges
    |> Enum.filter(&(&1.from == node_id))
    |> Enum.map(fn edge ->
      label =
        edge.attrs["label"]
        |> case do
          value when is_binary(value) and value != "" -> value
          _ -> edge.to
        end

      %{key: accelerator_key(label), label: label, to: edge.to}
    end)
  end

  defp accelerator_key(label) do
    value = to_string(label)

    cond do
      Regex.match?(~r/^\[([A-Za-z0-9])\]/, value) ->
        [_, key] = Regex.run(~r/^\[([A-Za-z0-9])\]/, value)
        String.upcase(key)

      Regex.match?(~r/^([A-Za-z0-9])\)/, value) ->
        [_, key] = Regex.run(~r/^([A-Za-z0-9])\)/, value)
        String.upcase(key)

      Regex.match?(~r/^([A-Za-z0-9])\s*-\s*/, value) ->
        [_, key] = Regex.run(~r/^([A-Za-z0-9])\s*-\s*/, value)
        String.upcase(key)

      true ->
        value
        |> String.trim()
        |> String.first()
        |> case do
          nil -> ""
          key -> String.upcase(key)
        end
    end
  end

  defp normalize_token(nil), do: ""

  defp normalize_token(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end
end
