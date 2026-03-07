defmodule AttractorEx.Interviewers.Callback do
  @moduledoc false

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
end
