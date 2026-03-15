defmodule AttractorEx.HTTP.QuestionRecord do
  @moduledoc """
  Typed persisted question metadata for HTTP-managed human gates.
  """

  @enforce_keys [:id, :inserted_at]
  defstruct [
    :id,
    :text,
    :type,
    :multiple,
    :required,
    :options,
    :timeout_seconds,
    :metadata,
    :inserted_at,
    :waiter,
    :ref
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          text: String.t() | nil,
          type: String.t() | nil,
          multiple: boolean() | nil,
          required: boolean() | nil,
          options: [map()],
          timeout_seconds: number() | nil,
          metadata: map(),
          inserted_at: String.t(),
          waiter: pid() | nil,
          ref: reference() | nil
        }

  @spec from_map(map()) :: t()
  def from_map(question) when is_map(question) do
    %__MODULE__{
      id: Map.get(question, "id") || Map.get(question, :id),
      text:
        Map.get(question, "text") || Map.get(question, :text) || Map.get(question, "prompt") ||
          Map.get(question, :prompt),
      type: Map.get(question, "type") || Map.get(question, :type),
      multiple: Map.get(question, "multiple") || Map.get(question, :multiple),
      required: Map.get(question, "required") || Map.get(question, :required),
      options: Map.get(question, "options") || Map.get(question, :options) || [],
      timeout_seconds:
        Map.get(question, "timeout_seconds") || Map.get(question, :timeout_seconds),
      metadata: Map.get(question, "metadata") || Map.get(question, :metadata) || %{},
      inserted_at:
        Map.get(question, "inserted_at") || Map.get(question, :inserted_at) || now_iso8601(),
      waiter: Map.get(question, :waiter),
      ref: Map.get(question, :ref)
    }
  end

  @spec to_public_map(t()) :: map()
  def to_public_map(%__MODULE__{} = question) do
    %{
      "id" => question.id,
      "text" => question.text,
      "type" => question.type,
      "multiple" => question.multiple,
      "required" => question.required,
      "options" => question.options,
      "timeout_seconds" => question.timeout_seconds,
      "metadata" => question.metadata,
      "inserted_at" => question.inserted_at
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  @spec serialize(t()) :: map()
  def serialize(%__MODULE__{} = question), do: to_public_map(question)

  defp now_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
