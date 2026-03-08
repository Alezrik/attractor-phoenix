defmodule AttractorEx.Interviewers.AutoApprove do
  @moduledoc """
  Deterministic interviewer that auto-selects a configured answer or the first choice.

  This adapter is mainly useful for tests and non-interactive automation.
  """

  @behaviour AttractorEx.Interviewer

  alias AttractorEx.Interviewers.Payload

  @impl true
  def ask(node, choices, _context, opts) do
    question = Payload.question(node, choices)
    configured = opts[:answer] || opts[:choice]

    case configured do
      nil -> choose_first(choices)
      value -> {:ok, Payload.normalize_single_answer(value, question)}
    end
  end

  @impl true
  def ask_multiple(node, choices, _context, opts) do
    question = Payload.question(node, choices)
    configured = opts[:choices] || opts[:answer] || opts[:choice]

    case configured do
      nil ->
        case choose_first(choices) do
          {:ok, value} -> {:ok, [value]}
          other -> other
        end

      value ->
        {:ok, Payload.normalize_multiple_answer(value, question)}
    end
  end

  @impl true
  def inform(_node, _payload, _context, _opts), do: :ok

  defp choose_first([%{key: key} | _]) when is_binary(key) and key != "", do: {:ok, key}
  defp choose_first([%{to: to} | _]), do: {:ok, to}
  defp choose_first(_), do: {:timeout}
end
