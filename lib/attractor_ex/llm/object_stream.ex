defmodule AttractorEx.LLM.ObjectStream do
  @moduledoc """
  Incremental JSON object streaming helpers for normalized LLM event streams.

  The transformer understands two practical patterns:

  1. newline-delimited JSON (`NDJSON`) values emitted in text deltas
  2. full JSON documents that become valid as the accumulated text grows
  """

  alias AttractorEx.LLM.{StreamEvent, Response}

  @type state :: %{
          line_buffer: String.t(),
          document_buffer: String.t(),
          last_document_hash: integer() | nil
        }

  @spec insert_object_events(Enumerable.t()) :: Enumerable.t()
  def insert_object_events(events) do
    Stream.transform(events, initial_state(), &handle_event/2)
  end

  defp initial_state do
    %{line_buffer: "", document_buffer: "", last_document_hash: nil}
  end

  defp handle_event(%StreamEvent{type: :text_delta, text: text} = event, state) do
    {object_events, next_state} = decode_incremental(text || "", state)
    {[event | object_events], next_state}
  end

  defp handle_event(%StreamEvent{type: :response, response: %Response{text: text}} = event, state) do
    {object_events, next_state} = decode_incremental(text || "", state)
    {[event | object_events], next_state}
  end

  defp handle_event(%StreamEvent{} = event, state), do: {[event], state}
  defp handle_event(event, state), do: {[event], state}

  defp decode_incremental(chunk, state) do
    line_source = state.line_buffer <> chunk
    document_buffer = state.document_buffer <> chunk

    {line_events, line_buffer} = decode_lines(line_source)
    {document_events, document_hash} = decode_document(document_buffer, state.last_document_hash)

    next_state = %{
      line_buffer: line_buffer,
      document_buffer: document_buffer,
      last_document_hash: document_hash
    }

    {line_events ++ document_events, next_state}
  end

  defp decode_lines(source) do
    segments = String.split(source, "\n")

    case List.pop_at(segments, -1) do
      {line_buffer, complete_lines} ->
        complete_events =
          complete_lines
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.flat_map(&decode_json_value/1)

        trailing_events =
          line_buffer
          |> to_string()
          |> String.trim()
          |> decode_json_value()

        {complete_events ++ trailing_events, line_buffer || ""}
    end
  end

  defp decode_document("", last_hash), do: {[], last_hash}

  defp decode_document(document_buffer, last_hash) do
    trimmed = String.trim(document_buffer)

    case Jason.decode(trimmed) do
      {:ok, value} when is_map(value) or is_list(value) ->
        hash = :erlang.phash2(value)

        if hash == last_hash do
          {[], last_hash}
        else
          {[%StreamEvent{type: :object_delta, object: value}], hash}
        end

      _ ->
        {[], last_hash}
    end
  end

  defp decode_json_value(text) do
    case Jason.decode(text) do
      {:ok, value} when is_map(value) or is_list(value) ->
        [%StreamEvent{type: :object_delta, object: value}]

      _ ->
        []
    end
  end
end
