defmodule AttractorEx.Handlers.WaitForHuman do
  @moduledoc false

  alias AttractorEx.{Graph, HumanGate, Outcome}
  alias AttractorEx.Interviewers.Payload

  def execute(node, context, %Graph{} = graph, _stage_dir, opts) do
    choices = HumanGate.choices_for(node.id, graph)
    multiple? = multiple_choice?(node)

    cond do
      choices == [] ->
        Outcome.fail("No outgoing edges for human gate")

      true ->
        case human_answer(context, node, choices, opts, multiple?) do
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

  defp resolve_answer(node, answers, choices) when is_list(answers) do
    normalized_answers =
      answers
      |> Enum.map(&normalize_token/1)
      |> Enum.reject(&(&1 == ""))

    cond do
      normalized_answers == [] ->
        resolve_answer(node, "", choices)

      Enum.any?(normalized_answers, &(&1 in ["skip", "skipped"])) ->
        Outcome.fail("human skipped interaction")

      Enum.any?(normalized_answers, &(&1 in ["timeout", "timed_out"])) ->
        resolve_answer(node, "timeout", choices)

      true ->
        matched_choices =
          answers
          |> Enum.map(&select_choice(&1, choices))
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq_by(& &1.to)

        case matched_choices do
          [] ->
            select_first_choice(choices)

          selected ->
            outcome_for_choices(selected)
        end
    end
  end

  defp resolve_answer(node, answer, choices) do
    normalized_answer = normalize_token(answer)

    cond do
      normalized_answer == "" ->
        resolve_blank_answer(node, choices)

      normalized_answer in ["timeout", "timed_out"] ->
        resolve_timeout_answer(node, choices)

      normalized_answer in ["skip", "skipped"] ->
        Outcome.fail("human skipped interaction")

      true ->
        resolve_selected_answer(answer, choices)
    end
  end

  defp resolve_blank_answer(node, choices) do
    case valid_default_choice(node) do
      {:ok, value} ->
        case select_choice(value, choices) do
          nil -> Outcome.retry("human gate blank answer, no valid default")
          choice -> outcome_for_choice(choice)
        end

      :error ->
        Outcome.retry("human gate requires answer in context.human.answers.#{node.id}")
    end
  end

  defp resolve_timeout_answer(node, choices) do
    case valid_default_choice(node) do
      {:ok, value} ->
        case select_choice(value, choices) do
          nil -> Outcome.retry("human gate timeout, no valid default")
          choice -> outcome_for_choice(choice)
        end

      :error ->
        Outcome.retry("human gate timeout, no default")
    end
  end

  defp resolve_selected_answer(answer, choices) do
    case select_choice(answer, choices) do
      nil -> select_first_choice(choices)
      choice -> outcome_for_choice(choice)
    end
  end

  defp select_choice(nil, _choices), do: nil

  defp select_choice(%{} = choice, choices) do
    cond do
      Map.has_key?(choice, :to) or Map.has_key?(choice, "to") ->
        %{
          key: Map.get(choice, :key) || Map.get(choice, "key"),
          label: Map.get(choice, :label) || Map.get(choice, "label"),
          to: Map.get(choice, :to) || Map.get(choice, "to")
        }

      true ->
        extract_structured_answer(choice)
        |> select_choice(choices)
    end
  end

  defp select_choice(value, choices) do
    HumanGate.match_choice(value, choices)
    |> case do
      nil -> nil
      choice -> choice
    end
  end

  defp outcome_for_choice(choice) do
    outcome_for_choices([choice])
  end

  defp outcome_for_choices(choices) do
    selected_keys = Enum.map(choices, & &1.key)
    selected_labels = Enum.map(choices, & &1.label)
    selected_targets = choices |> Enum.map(& &1.to) |> Enum.uniq()

    %Outcome{
      status: :success,
      suggested_next_ids: selected_targets,
      context_updates: %{
        "human" => %{
          "gate" => %{
            "selected" => List.first(selected_keys),
            "label" => List.first(selected_labels),
            "selected_many" => selected_keys,
            "labels" => selected_labels,
            "targets" => selected_targets
          }
        }
      }
    }
  end

  defp select_first_choice([choice | _rest]), do: outcome_for_choice(choice)
  defp select_first_choice([]), do: nil

  defp human_answer(context, node_id) do
    case get_in(context, ["human", "answers", node_id]) ||
           get_in(context, ["human", node_id, "answer"]) do
      nil -> :missing
      value -> {:ok, value}
    end
  end

  defp human_answer(context, node, choices, opts, multiple?) do
    case human_answer(context, node.id) do
      {:ok, value} -> {:ok, value}
      :missing -> interviewer_answer(node, choices, context, opts, multiple?)
    end
  end

  defp interviewer_answer(node, choices, context, opts, multiple?) do
    question = Payload.question(node, choices)

    with {:ok, module} <- resolve_interviewer(opts),
         response <-
           ask_interviewer(module, node, choices, context, interviewer_opts(opts), multiple?) do
      normalize_interviewer_response(response, question, multiple?)
    else
      :none -> :missing
      {:error, reason} -> {:error, reason}
    end
  end

  defp ask_interviewer(module, node, choices, context, opts, true) do
    _ = Code.ensure_loaded(module)

    cond do
      function_exported?(module, :ask_multiple, 4) ->
        module.ask_multiple(node, choices, context, opts)

      function_exported?(module, :ask, 4) ->
        case module.ask(node, choices, context, opts) do
          {:ok, value} when is_list(value) -> {:ok, value}
          {:ok, value} -> {:ok, [value]}
          other -> other
        end

      true ->
        {:error, "interviewer module does not implement ask/4: #{inspect(module)}"}
    end
  end

  defp ask_interviewer(module, node, choices, context, opts, false) do
    _ = Code.ensure_loaded(module)
    module.ask(node, choices, context, opts)
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
        if Code.ensure_loaded?(module) and function_exported?(module, :ask, 4) do
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
    |> Keyword.merge(
      Keyword.take(opts, [
        :callback,
        :callback_multiple,
        :callback_inform,
        :answer,
        :choice,
        :choices,
        :queue,
        :recording_sink
      ])
    )
    |> maybe_put_recording_inner(opts[:interviewer])
  end

  defp maybe_put_recording_inner(opts, {:recording, module}) when is_atom(module),
    do: Keyword.put(opts, :inner, module)

  defp maybe_put_recording_inner(opts, _interviewer), do: opts

  defp normalize_interviewer_response({:ok, value}, question, true) do
    {:ok, Payload.normalize_multiple_answer(value, question)}
  end

  defp normalize_interviewer_response({:ok, value}, question, false) do
    {:ok, Payload.normalize_single_answer(value, question)}
  end

  defp normalize_interviewer_response({:error, reason}, _question, _multiple?),
    do: {:error, to_string(reason)}

  defp normalize_interviewer_response({:timeout}, _question, _multiple?), do: {:ok, "timeout"}
  defp normalize_interviewer_response(:timeout, _question, _multiple?), do: {:ok, "timeout"}
  defp normalize_interviewer_response({:skip}, _question, _multiple?), do: {:ok, "skip"}
  defp normalize_interviewer_response(:skip, _question, _multiple?), do: {:ok, "skip"}
  defp normalize_interviewer_response(nil, _question, _multiple?), do: :missing

  defp normalize_interviewer_response(value, question, true) do
    {:ok, Payload.normalize_multiple_answer(value, question)}
  end

  defp normalize_interviewer_response(value, question, false) do
    {:ok, Payload.normalize_single_answer(value, question)}
  end

  defp normalize_token(nil), do: ""
  defp normalize_token(%{} = value), do: normalize_token(extract_structured_answer(value))
  defp normalize_token([value]), do: normalize_token(value)
  defp normalize_token(value) when is_boolean(value), do: if(value, do: "true", else: "false")

  defp normalize_token(value) do
    HumanGate.normalize_token(value)
  end

  defp multiple_choice?(node) do
    truthy?(Map.get(node.attrs, "human.multiple"))
  end

  defp truthy?(value) when is_boolean(value), do: value

  defp truthy?(value) when is_binary(value) do
    String.downcase(String.trim(value)) in ["true", "1", "yes"]
  end

  defp truthy?(_value), do: false

  defp valid_default_choice(node) do
    case node.attrs["human.default_choice"] do
      value when is_binary(value) ->
        if String.trim(value) == "", do: :error, else: {:ok, value}

      _ ->
        :error
    end
  end

  defp extract_structured_answer(answer) do
    Payload.extract_answer(answer)
  end
end
