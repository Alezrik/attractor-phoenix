defmodule AttractorEx.Interviewers.Queue do
  @moduledoc false

  @behaviour AttractorEx.Interviewer

  @impl true
  def ask(_node, _choices, _context, opts) do
    queue = opts[:queue]

    cond do
      is_list(queue) ->
        pop_list(queue)

      is_pid(queue) ->
        pop_agent(queue)

      true ->
        {:error, "queue interviewer requires :queue list or Agent pid"}
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

  defp pop_list([head | _tail]), do: {:ok, head}
  defp pop_list([]), do: {:timeout}

  defp pop_agent(pid) do
    Agent.get_and_update(pid, fn
      [head | tail] -> {{:ok, head}, tail}
      [] -> {{:timeout}, []}
      value -> {{:error, "unsupported queue value: #{inspect(value)}"}, value}
    end)
  rescue
    error -> {:error, Exception.message(error)}
  end
end
