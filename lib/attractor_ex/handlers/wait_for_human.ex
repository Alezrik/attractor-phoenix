defmodule AttractorEx.Handlers.WaitForHuman do
  @moduledoc false

  alias AttractorEx.{Graph, HumanGate, Outcome}

  def execute(node, context, %Graph{} = graph, _stage_dir, opts) do
    choices = HumanGate.choices_for(node.id, graph)

    cond do
      choices == [] ->
        Outcome.fail("No outgoing edges for human gate")

      true ->
        case human_answer(context, node, choices, opts) do
          {:ok, answer} -> resolve_answer(node, answer, choices)
          :missing -> resolve_answer(node, nil, choices)
          {:error, reason} -> Outcome.retry("human gate interviewer error: #{reason}")
        end
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
      normalized_answer == "" ->
        case node.attrs["human.default_choice"] do
          value when is_binary(value) ->
            if String.trim(value) != "" do
              select_choice(value, choices) ||
                Outcome.retry("human gate blank answer, no valid default")
            else
              Outcome.retry("human gate requires answer in context.human.answers.#{node.id}")
            end

          _ ->
            Outcome.retry("human gate requires answer in context.human.answers.#{node.id}")
        end

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
        select_choice(answer, choices) ||
          Outcome.retry("human gate answer did not match any choice")
    end
  end

  defp select_choice(nil, _choices), do: nil
  defp select_choice(%{} = choice, _choices), do: outcome_for_choice(choice)

  defp select_choice(value, choices) do
    HumanGate.match_choice(value, choices)
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
    case get_in(context, ["human", "answers", node_id]) ||
           get_in(context, ["human", node_id, "answer"]) do
      nil -> :missing
      value -> {:ok, value}
    end
  end

  defp human_answer(context, node, choices, opts) do
    case human_answer(context, node.id) do
      {:ok, value} -> {:ok, value}
      :missing -> interviewer_answer(node, choices, context, opts)
    end
  end

  defp interviewer_answer(node, choices, context, opts) do
    with {:ok, module} <- resolve_interviewer(opts),
         response <- module.ask(node, choices, context, interviewer_opts(opts)) do
      normalize_interviewer_response(response)
    else
      :none -> :missing
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_interviewer(opts) do
    case opts[:interviewer] do
      nil ->
        :none

      :auto_approve ->
        {:ok, AttractorEx.Interviewers.AutoApprove}

      :console ->
        {:ok, AttractorEx.Interviewers.Console}

      :callback ->
        {:ok, AttractorEx.Interviewers.Callback}

      :queue ->
        {:ok, AttractorEx.Interviewers.Queue}

      :recording ->
        {:ok, AttractorEx.Interviewers.Recording}

      {:recording, module} when is_atom(module) ->
        {:ok, AttractorEx.Interviewers.Recording}

      module when is_atom(module) ->
        if function_exported?(module, :ask, 4) do
          {:ok, module}
        else
          {:error, "interviewer module does not implement ask/4: #{inspect(module)}"}
        end

      value ->
        {:error, "invalid interviewer: #{inspect(value)}"}
    end
  end

  defp interviewer_opts(opts) do
    opts
    |> Keyword.get(:interviewer_opts, [])
    |> Keyword.merge(Keyword.take(opts, [:callback, :choice, :choices, :queue, :recording_sink]))
    |> maybe_put_recording_inner(opts[:interviewer])
  end

  defp maybe_put_recording_inner(opts, {:recording, module}) when is_atom(module),
    do: Keyword.put(opts, :inner, module)

  defp maybe_put_recording_inner(opts, _interviewer), do: opts

  defp normalize_interviewer_response({:ok, value}), do: {:ok, value}
  defp normalize_interviewer_response({:error, reason}), do: {:error, to_string(reason)}
  defp normalize_interviewer_response({:timeout}), do: {:ok, "timeout"}
  defp normalize_interviewer_response(:timeout), do: {:ok, "timeout"}
  defp normalize_interviewer_response({:skip}), do: {:ok, "skip"}
  defp normalize_interviewer_response(:skip), do: {:ok, "skip"}
  defp normalize_interviewer_response(nil), do: :missing
  defp normalize_interviewer_response(value), do: {:ok, value}
  defp normalize_token(nil), do: ""

  defp normalize_token(value) do
    HumanGate.normalize_token(value)
  end
end
