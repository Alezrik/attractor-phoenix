defmodule AttractorEx.Interviewers.Recording do
  @moduledoc false

  @behaviour AttractorEx.Interviewer

  alias AttractorEx.Interviewers.Payload

  @impl true
  def ask(node, choices, context, opts) do
    question = Payload.question(node, choices)
    record(opts, %{event: :ask, node_id: node.id, choices: choices, question: question})
    delegate(:ask, node, choices, context, opts, question, false)
  end

  @impl true
  def ask_multiple(node, choices, context, opts) do
    question = Payload.question(node, choices)
    record(opts, %{event: :ask_multiple, node_id: node.id, choices: choices, question: question})
    delegate(:ask_multiple, node, choices, context, opts, question, true)
  end

  @impl true
  def inform(node, payload, context, opts) do
    record(opts, %{event: :inform, node_id: node.id, payload: payload})
    delegate_inform(node, payload, context, opts)
  end

  defp delegate(fun, node, payload, context, opts, question, multiple?) do
    inner =
      opts[:inner]
      |> Kernel.||(opts[:recording_inner])
      |> Kernel.||(:auto_approve)
      |> resolve_inner()

    _ = Code.ensure_loaded(inner)

    cond do
      function_exported?(inner, fun, 4) ->
        apply(inner, fun, [node, payload, context, opts])
        |> record_result(opts, question, multiple?)

      fun == :ask_multiple and function_exported?(inner, :ask, 4) ->
        case inner.ask(node, payload, context, opts) do
          {:ok, value} -> {:ok, Payload.normalize_multiple_answer(value, question)}
          other -> other
        end
        |> record_result(opts, question, multiple?)

      true ->
        :ok
    end
  end

  defp resolve_inner(:auto_approve), do: AttractorEx.Interviewers.AutoApprove
  defp resolve_inner(:callback), do: AttractorEx.Interviewers.Callback
  defp resolve_inner(:console), do: AttractorEx.Interviewers.Console
  defp resolve_inner(:queue), do: AttractorEx.Interviewers.Queue
  defp resolve_inner(module) when is_atom(module), do: module

  defp delegate_inform(node, payload, context, opts) do
    inner =
      opts[:inner]
      |> Kernel.||(opts[:recording_inner])
      |> Kernel.||(:auto_approve)
      |> resolve_inner()

    _ = Code.ensure_loaded(inner)

    if function_exported?(inner, :inform, 4) do
      inner.inform(node, payload, context, opts)
    else
      :ok
    end
  end

  defp record(opts, event) do
    case opts[:recording_sink] do
      pid when is_pid(pid) ->
        Agent.update(pid, fn events -> events ++ [event] end)

      sink when is_function(sink, 1) ->
        sink.(event)

      _ ->
        :ok
    end
  rescue
    _error -> :ok
  end

  defp record_result({:ok, value} = result, opts, question, multiple?) do
    normalized =
      if multiple? do
        Payload.normalize_multiple_answer(value, question)
      else
        Payload.normalize_single_answer(value, question)
      end

    record(opts, %{
      event: :answer,
      node_id: question.id,
      answer: normalized,
      answer_payload: Payload.answer_payload(value, %{question | multiple: multiple?})
    })

    result
  end

  defp record_result(result, _opts, _question, _multiple?), do: result
end
