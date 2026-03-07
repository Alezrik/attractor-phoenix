defmodule AttractorEx.Interviewers.AutoApprove do
  @moduledoc false

  @behaviour AttractorEx.Interviewer

  @impl true
  def ask(_node, choices, _context, opts) do
    configured = opts[:choice]

    case configured do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> choose_first(choices)
    end
  end

  @impl true
  def ask_multiple(_node, choices, _context, opts) do
    configured = opts[:choices]

    cond do
      is_list(configured) and configured != [] ->
        {:ok, configured}

      true ->
        case choose_first(choices) do
          {:ok, value} -> {:ok, [value]}
          other -> other
        end
    end
  end

  @impl true
  def inform(_node, _payload, _context, _opts), do: :ok

  defp choose_first([%{key: key} | _]) when is_binary(key) and key != "", do: {:ok, key}
  defp choose_first([%{to: to} | _]), do: {:ok, to}
  defp choose_first(_), do: {:timeout}
end
