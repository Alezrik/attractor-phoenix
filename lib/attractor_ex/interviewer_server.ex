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
        emit(opts, %{
          type: "InterviewCompleted",
          stage: node.id,
          answer: answer,
          question: public_question(question)
        })

        {:ok, answer}
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
    %{
      id: node.id,
      ref: make_ref(),
      waiter: self(),
      text: Map.get(node.attrs, "prompt", "Choose a path"),
      type: "MULTIPLE_CHOICE",
      options: choices,
      default: Map.get(node.attrs, "human.default_choice"),
      timeout_seconds: timeout_ms / 1000,
      stage: node.id,
      metadata: %{
        "node_id" => node.id,
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
end
