defmodule AttractorEx.Interviewers.Server do
  @moduledoc """
  HTTP-oriented interviewer used by `AttractorEx.HTTP`.

  Questions are registered with `AttractorEx.HTTP.Manager`, exposed as pending HTTP
  resources, and completed when an external client submits an answer.
  """

  @behaviour AttractorEx.Interviewer

  alias AttractorEx.HTTP.Manager
  alias AttractorEx.Interviewers.Payload

  @impl true
  def ask(node, choices, context, opts) do
    pipeline_id = opts[:pipeline_id] || context["run_id"]
    manager = Keyword.get(opts, :manager, Manager)
    timeout_ms = Payload.timeout_ms(node.attrs["human.timeout"])
    question = build_question(node, choices, timeout_ms)

    :ok = Manager.register_question(manager, pipeline_id, question)

    emit(opts, %{
      type: "InterviewStarted",
      stage: node.id,
      question: public_question(question)
    })

    receive do
      {:pipeline_answer, ref, answer} when ref == question.ref ->
        normalized_answer =
          if question.multiple do
            Payload.normalize_multiple_answer(answer, question)
          else
            Payload.normalize_single_answer(answer, question)
          end

        emit(opts, %{
          type: "InterviewCompleted",
          stage: node.id,
          answer: normalized_answer,
          answer_payload: Payload.answer_payload(answer, question),
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
    Payload.question(node, choices, timeout: timeout_ms)
    |> Map.merge(%{ref: make_ref(), waiter: self()})
  end

  defp public_question(question), do: Map.drop(question, [:waiter, :ref])

  defp emit(opts, event) do
    case opts[:event_observer] do
      fun when is_function(fun, 1) -> fun.(event)
      _ -> :ok
    end
  end
end
