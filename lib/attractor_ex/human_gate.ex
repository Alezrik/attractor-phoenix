defmodule AttractorEx.HumanGate do
  @moduledoc """
  Helper functions for building and matching `wait.human` choices.

  This module converts outgoing edges into normalized selectable options and performs
  tolerant matching against keys, labels, and destination node IDs.
  """

  alias AttractorEx.Graph

  @doc "Builds the available choices for a human-gate node from its outgoing edges."
  def choices_for(node_id, %Graph{} = graph) do
    graph.edges
    |> Enum.filter(&(&1.from == node_id))
    |> Enum.map(fn edge ->
      label =
        edge.attrs["label"]
        |> case do
          value when is_binary(value) and value != "" -> value
          _ -> edge.to
        end

      %{key: accelerator_key(label), label: label, to: edge.to}
    end)
  end

  @doc "Finds the first matching choice for a human answer token."
  def match_choice(value, choices) do
    normalized = normalize_token(value)

    Enum.find(choices, fn choice ->
      normalize_token(choice.key) == normalized or
        normalize_token(choice.label) == normalized or
        normalize_token(choice.to) == normalized
    end)
  end

  @doc "Normalizes answer tokens for case-insensitive matching."
  def normalize_token(nil), do: ""

  def normalize_token(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
  end

  defp accelerator_key(label) do
    value = to_string(label)

    cond do
      Regex.match?(~r/^\[([A-Za-z0-9])\]/, value) ->
        [_, key] = Regex.run(~r/^\[([A-Za-z0-9])\]/, value)
        String.upcase(key)

      Regex.match?(~r/^([A-Za-z0-9])\)/, value) ->
        [_, key] = Regex.run(~r/^([A-Za-z0-9])\)/, value)
        String.upcase(key)

      Regex.match?(~r/^([A-Za-z0-9])\s*-\s*/, value) ->
        [_, key] = Regex.run(~r/^([A-Za-z0-9])\s*-\s*/, value)
        String.upcase(key)

      true ->
        value
        |> String.trim()
        |> String.first()
        |> case do
          nil -> ""
          key -> String.upcase(key)
        end
    end
  end
end
