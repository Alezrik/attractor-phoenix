defmodule AttractorEx.LLM.MessagePart do
  @moduledoc """
  Tagged content part used by `AttractorEx.LLM.Message`.

  The unified client still treats multimodal payloads as pass-through data for provider
  adapters, but this struct gives requests a stable representation for richer content.
  """

  @typedoc "Known content part kinds carried by the normalized message model."
  @type part_type ::
          :text
          | :image
          | :audio
          | :document
          | :tool_call
          | :tool_result
          | :thinking
          | :json

  defstruct type: :text, text: nil, data: %{}, mime_type: nil

  @type t :: %__MODULE__{
          type: part_type(),
          text: String.t() | nil,
          data: map(),
          mime_type: String.t() | nil
        }

  @doc false
  @spec text_projection(t() | map() | term()) :: String.t()
  def text_projection(%__MODULE__{type: :text, text: text}) when is_binary(text), do: text
  def text_projection(%__MODULE__{type: :thinking, text: text}) when is_binary(text), do: text

  def text_projection(%__MODULE__{type: type, text: text}) do
    label = type |> to_string() |> String.replace("_", " ")

    case text do
      value when is_binary(value) and value != "" -> "[#{label}: #{value}]"
      _ -> "[#{label}]"
    end
  end

  def text_projection(%{"type" => type} = part) do
    text_projection(%__MODULE__{
      type: normalize_type(type),
      text: Map.get(part, "text") || Map.get(part, :text),
      data: Map.get(part, "data") || Map.get(part, :data) || %{},
      mime_type: Map.get(part, "mime_type") || Map.get(part, :mime_type)
    })
  end

  def text_projection(_part), do: ""

  defp normalize_type(type) when is_atom(type), do: type

  defp normalize_type(type) when is_binary(type) do
    case type do
      "text" -> :text
      "image" -> :image
      "audio" -> :audio
      "document" -> :document
      "tool_call" -> :tool_call
      "tool_result" -> :tool_result
      "thinking" -> :thinking
      "json" -> :json
      _ -> :text
    end
  end

  defp normalize_type(_type), do: :text
end
