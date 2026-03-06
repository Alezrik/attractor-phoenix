defmodule AttractorEx.Handlers.Codergen do
  @moduledoc false

  alias AttractorEx.{Outcome, SimulationBackend}

  def execute(node, context, graph, stage_dir, opts) do
    prompt =
      node.prompt
      |> blank_to_nil()
      |> case do
        nil -> blank_to_nil(node.attrs["label"]) || ""
        value -> value
      end
      |> String.replace("$goal", Map.get(graph.attrs, "goal", ""))

    if String.trim(prompt) == "" do
      Outcome.fail("Codergen node requires a non-empty prompt or label.")
    else
      backend = Keyword.get(opts, :codergen_backend, SimulationBackend)
      _ = File.mkdir_p(stage_dir)
      _ = File.write(Path.join(stage_dir, "prompt.md"), prompt)

      result =
        case backend.run(node, prompt, context) do
          %Outcome{} = outcome ->
            outcome

          value ->
            response = to_string(value)
            _ = File.write(Path.join(stage_dir, "response.md"), response)
            Outcome.success(%{"responses" => %{node.id => response}}, "Codergen completed")
        end

      result
      |> maybe_write_response(stage_dir, node.id)
      |> maybe_write_status(stage_dir)
    end
  end

  defp maybe_write_response(outcome, stage_dir, node_id) do
    response =
      outcome.context_updates
      |> Map.get("responses", %{})
      |> Map.get(node_id)

    if is_binary(response), do: File.write(Path.join(stage_dir, "response.md"), response)
    outcome
  end

  defp maybe_write_status(outcome, stage_dir) do
    status_payload = %{
      status: outcome.status,
      notes: outcome.notes,
      failure_reason: outcome.failure_reason,
      context_updates: outcome.context_updates,
      preferred_label: outcome.preferred_label,
      suggested_next_ids: outcome.suggested_next_ids
    }

    with {:ok, encoded} <- Jason.encode(status_payload, pretty: true) do
      _ = File.write(Path.join(stage_dir, "status.json"), encoded)
    end

    outcome
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    trimmed = value |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end
end
