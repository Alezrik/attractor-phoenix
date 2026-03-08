defmodule AttractorEx.StatusContract do
  @moduledoc """
  Serializes handler outcomes into the `status.json` artifact contract.

  The payload shape is aligned with the Appendix C-style status fields used by the
  upstream Attractor documentation while preserving a few backward-compatible aliases.
  """

  alias AttractorEx.Outcome

  @doc "Writes a pretty-printed `status.json` payload to disk."
  def write_status_file(path, %Outcome{} = outcome) do
    with {:ok, encoded} <- Jason.encode(status_file_payload(outcome), pretty: true) do
      File.write(path, encoded)
    end
  end

  @doc "Builds the on-disk status-file payload for an outcome."
  def status_file_payload(%Outcome{} = outcome) do
    outcome_value = Atom.to_string(outcome.status)
    preferred = blank_to_nil(outcome.preferred_label)

    %{
      "outcome" => outcome_value,
      "preferred_next_label" => preferred,
      "suggested_next_ids" => outcome.suggested_next_ids || [],
      "context_updates" => outcome.context_updates || %{},
      "notes" => outcome.notes,
      "status" => outcome_value,
      "preferred_label" => preferred
    }
    |> maybe_put("failure_reason", blank_to_nil(outcome.failure_reason))
    |> maybe_put("error_category", normalize_category(outcome.failure_category))
  end

  @doc "Builds a normalized runtime map representation of an outcome."
  def serialize_outcome(%Outcome{} = outcome) do
    %{
      status: outcome.status,
      outcome: Atom.to_string(outcome.status),
      notes: outcome.notes,
      failure_reason: outcome.failure_reason,
      failure_category: outcome.failure_category,
      context_updates: outcome.context_updates,
      preferred_label: outcome.preferred_label,
      preferred_next_label: outcome.preferred_label,
      suggested_next_ids: outcome.suggested_next_ids
    }
  end

  defp normalize_category(nil), do: nil
  defp normalize_category(category), do: Atom.to_string(category)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    trimmed = value |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end
end
