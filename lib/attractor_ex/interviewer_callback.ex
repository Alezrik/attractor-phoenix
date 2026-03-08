defmodule AttractorEx.Interviewers.Callback do
  @moduledoc """
  Interviewer that delegates question handling to caller-provided functions.
  """

  @behaviour AttractorEx.Interviewer

  @impl true
  def ask(node, choices, context, opts) do
    callback = opts[:callback]

    cond do
      is_function(callback, 3) ->
        callback.(node, choices, context)

      is_function(callback, 4) ->
        callback.(node, choices, context, opts)

      true ->
        {:error, "callback interviewer requires :callback function"}
    end
  end

  @impl true
  def ask_multiple(node, choices, context, opts) do
    callback = opts[:callback_multiple] || opts[:callback]

    cond do
      is_function(callback, 3) -> callback.(node, choices, context)
      is_function(callback, 4) -> callback.(node, choices, context, opts)
      true -> {:error, "callback interviewer requires :callback or :callback_multiple function"}
    end
  end

  @impl true
  def inform(node, payload, context, opts) do
    callback = opts[:callback_inform] || opts[:callback]

    cond do
      is_function(callback, 3) -> callback.(node, payload, context)
      is_function(callback, 4) -> callback.(node, payload, context, opts)
      true -> :ok
    end
  end
end
