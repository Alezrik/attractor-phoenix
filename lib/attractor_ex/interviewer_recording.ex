defmodule AttractorEx.Interviewers.Recording do
  @moduledoc false

  @behaviour AttractorEx.Interviewer

  @impl true
  def ask(node, choices, context, opts) do
    record(opts, %{event: :ask, node_id: node.id, choices: choices})
    delegate(:ask, node, choices, context, opts)
  end

  @impl true
  def ask_multiple(node, choices, context, opts) do
    record(opts, %{event: :ask_multiple, node_id: node.id, choices: choices})
    delegate(:ask_multiple, node, choices, context, opts)
  end

  @impl true
  def inform(node, payload, context, opts) do
    record(opts, %{event: :inform, node_id: node.id, payload: payload})
    delegate(:inform, node, payload, context, opts)
  end

  defp delegate(fun, node, payload, context, opts) do
    inner =
      opts[:inner]
      |> Kernel.||(opts[:recording_inner])
      |> Kernel.||(:auto_approve)
      |> resolve_inner()

    _ = Code.ensure_loaded(inner)

    cond do
      function_exported?(inner, fun, 4) ->
        apply(inner, fun, [node, payload, context, opts])

      fun == :ask_multiple and function_exported?(inner, :ask, 4) ->
        case inner.ask(node, payload, context, opts) do
          {:ok, value} when is_list(value) -> {:ok, value}
          {:ok, value} -> {:ok, [value]}
          other -> other
        end

      true ->
        :ok
    end
  end

  defp resolve_inner(:auto_approve), do: AttractorEx.Interviewers.AutoApprove
  defp resolve_inner(:callback), do: AttractorEx.Interviewers.Callback
  defp resolve_inner(:console), do: AttractorEx.Interviewers.Console
  defp resolve_inner(:queue), do: AttractorEx.Interviewers.Queue
  defp resolve_inner(module) when is_atom(module), do: module

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
end
