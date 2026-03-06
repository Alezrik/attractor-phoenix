defmodule AttractorEx.Handlers.Codergen do
  @moduledoc false

  alias AttractorEx.LLM.{Client, Message, Request, Response}
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
      llm_client = Keyword.get(opts, :llm_client)
      backend = Keyword.get(opts, :codergen_backend, SimulationBackend)
      _ = File.mkdir_p(stage_dir)
      _ = File.write(Path.join(stage_dir, "prompt.md"), prompt)

      result =
        cond do
          match?(%Client{}, llm_client) ->
            run_with_llm_client(llm_client, node, prompt, context, opts)

          true ->
            case backend.run(node, prompt, context) do
              %Outcome{} = outcome ->
                outcome

              value ->
                response = to_string(value)
                _ = File.write(Path.join(stage_dir, "response.md"), response)
                Outcome.success(%{"responses" => %{node.id => response}}, "Codergen completed")
            end
        end

      result
      |> maybe_write_response(stage_dir, node.id)
      |> maybe_write_status(stage_dir)
    end
  end

  defp run_with_llm_client(client, node, prompt, _context, opts) do
    with {:ok, model} <- fetch_model(node, opts),
         request <- build_request(node, prompt, model, opts),
         {:ok, %Response{} = response, resolved_request} <-
           Client.complete_with_request(client, request) do
      Outcome.success(
        %{
          "responses" => %{node.id => response.text},
          "llm" => %{
            "provider" => resolved_request.provider,
            "model" => resolved_request.model,
            "finish_reason" => response.finish_reason,
            "usage" => stringify_map_keys(Map.from_struct(response.usage))
          }
        },
        "Codergen completed"
      )
    else
      {:error, :model_required} ->
        Outcome.fail(
          "Codergen llm_client requires node attribute `llm_model` (or opts[:llm_model])."
        )

      {:error, reason} ->
        Outcome.fail("LLM client error: #{inspect(reason)}")

      other ->
        Outcome.fail("Unexpected LLM client response: #{inspect(other)}")
    end
  end

  defp build_request(node, prompt, model, opts) do
    %Request{
      model: model,
      provider: blank_to_nil(node.attrs["llm_provider"]) || blank_to_nil(opts[:llm_provider]),
      messages: [%Message{role: :user, content: prompt}],
      max_tokens: parse_int(node.attrs["max_tokens"]),
      temperature: parse_float(node.attrs["temperature"]),
      reasoning_effort: node.attrs["reasoning_effort"] || "high",
      provider_options: node.attrs["provider_options"] || %{},
      metadata: %{"node_id" => node.id}
    }
  end

  defp fetch_model(node, opts) do
    case blank_to_nil(node.attrs["llm_model"]) || blank_to_nil(opts[:llm_model]) do
      nil -> {:error, :model_required}
      value -> {:ok, value}
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

  defp parse_int(nil), do: nil
  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_int(_), do: nil

  defp parse_float(nil), do: nil
  defp parse_float(value) when is_float(value), do: value
  defp parse_float(value) when is_integer(value), do: value * 1.0

  defp parse_float(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp parse_float(_), do: nil

  defp stringify_map_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Map.new()
  end
end
