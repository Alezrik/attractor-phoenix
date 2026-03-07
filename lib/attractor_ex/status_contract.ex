defmodule AttractorEx.StatusContract do
  @moduledoc false

  alias AttractorEx.Outcome

  def write_status_file(path, %Outcome{} = outcome) do
    with {:ok, encoded} <- Jason.encode(status_file_payload(outcome), pretty: true) do
      File.write(path, encoded)
    end
  end

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
