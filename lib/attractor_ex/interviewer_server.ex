defmodule AttractorEx.Interviewers.Server do
  @moduledoc false

  @behaviour AttractorEx.Interviewer

  alias AttractorEx.HTTP.Manager

  @impl true
  def ask(node, choices, context, opts) do
    pipeline_id = opts[:pipeline_id] || context["run_id"]
    manager = Keyword.get(opts, :manager, Manager)
    timeout_ms = timeout_ms(node.attrs["human.timeout"])
    question = build_question(node, choices, timeout_ms)

    emit(opts, %{
      type: "InterviewStarted",
      stage: node.id,
      question: public_question(question)
    })

    :ok = Manager.register_question(manager, pipeline_id, question)

    receive do
      {:pipeline_answer, ref, answer} when ref == question.ref ->
        normalized_answer = normalize_answer(answer, question)

        emit(opts, %{
          type: "InterviewCompleted",
          stage: node.id,
          answer: normalized_answer,
          question: public_question(question)
        })

        {:ok, normalized_answer}
    after
      timeout_ms ->
        Manager.timeout_question(manager, pipeline_id, question.id)

        emit(opts, %{
          type: "InterviewTimeout",
          stage: node.id,
          duration_ms: timeout_ms,
          question: public_question(question)
        })

        {:timeout}
    end
  end

  @impl true
  def ask_multiple(node, choices, context, opts) do
    case ask(node, choices, context, opts) do
      {:ok, values} when is_list(values) -> {:ok, values}
      {:ok, value} -> {:ok, [value]}
      other -> other
    end
  end

  @impl true
  def inform(_node, _payload, _context, _opts), do: :ok

  defp build_question(node, choices, timeout_ms) do
    question_type = question_type(node, choices)

    %{
      id: node.id,
      ref: make_ref(),
      waiter: self(),
      text: Map.get(node.attrs, "prompt", "Choose a path"),
      type: question_type,
      options: choices,
      default: Map.get(node.attrs, "human.default_choice"),
      timeout_seconds: timeout_ms / 1000,
      stage: node.id,
      metadata: %{
        "node_id" => node.id,
        "question_type" => question_type,
        "timeout" => Map.get(node.attrs, "human.timeout"),
        "default_choice" => Map.get(node.attrs, "human.default_choice")
      }
    }
  end

  defp public_question(question), do: Map.drop(question, [:waiter, :ref])

  defp emit(opts, event) do
    case opts[:event_observer] do
      fun when is_function(fun, 1) -> fun.(event)
      _ -> :ok
    end
  end

  defp timeout_ms(value) when is_integer(value) and value > 0, do: value

  defp timeout_ms(value) when is_binary(value) do
    trimmed = String.trim(value)

    case Integer.parse(trimmed) do
      {parsed, ""} when parsed > 0 ->
        parsed * 1000

      _ ->
        case Regex.run(~r/^(\d+)(ms|s|m|h)$/, trimmed, capture: :all_but_first) do
          [amount, "ms"] -> String.to_integer(amount)
          [amount, "s"] -> String.to_integer(amount) * 1_000
          [amount, "m"] -> String.to_integer(amount) * 60_000
          [amount, "h"] -> String.to_integer(amount) * 3_600_000
          _ -> 60_000
        end
    end
  end

  defp timeout_ms(_value), do: 60_000

  defp question_type(node, choices) do
    cond do
      truthy?(Map.get(node.attrs, "human.multiple")) ->
        "MULTIPLE_CHOICE"

      choices == [] ->
        "FREEFORM"

      confirmation_choice?(choices) ->
        "CONFIRMATION"

      yes_no_choices?(choices) ->
        "YES_NO"

      true ->
        "MULTIPLE_CHOICE"
    end
  end

  defp confirmation_choice?([_choice]), do: true
  defp confirmation_choice?(_choices), do: false

  defp yes_no_choices?(choices) when length(choices) == 2 do
    normalized =
      choices
      |> Enum.flat_map(fn choice -> [choice[:key], choice[:label], choice[:to]] end)
      |> Enum.map(&normalize_token/1)
      |> Enum.reject(&(&1 == ""))

    Enum.any?(normalized, &(&1 in ["yes", "y", "approve", "approved"])) and
      Enum.any?(normalized, &(&1 in ["no", "n", "reject", "rejected"]))
  end

  defp yes_no_choices?(_choices), do: false

  defp normalize_token(nil), do: ""

  defp normalize_token(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp truthy?(value) when is_boolean(value), do: value
  defp truthy?(value) when is_binary(value), do: normalize_token(value) in ["true", "1", "yes"]
  defp truthy?(_value), do: false

  defp normalize_answer(answer, %{type: "YES_NO"}) when is_boolean(answer) do
    if answer, do: "yes", else: "no"
  end

  defp normalize_answer(answer, %{type: "CONFIRMATION"}) when is_boolean(answer) do
    if answer, do: "confirm", else: "cancel"
  end

  defp normalize_answer(answer, question) when is_map(answer) do
    candidate =
      answer["answer"] || answer[:answer] || answer["value"] || answer[:value] || answer["key"] ||
        answer[:key]

    normalize_answer(candidate, question)
  end

  defp normalize_answer(answer, question) when is_list(answer) do
    Enum.map(answer, &normalize_answer(&1, question))
  end

  defp normalize_answer(answer, _question) when is_binary(answer), do: String.trim(answer)
  defp normalize_answer(answer, _question), do: answer
end
