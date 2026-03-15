defmodule AttractorEx.HTTP.EventRecord do
  @moduledoc """
  Typed persisted event entry for HTTP-managed pipeline runs.
  """

  @enforce_keys [:sequence, :pipeline_id, :type, :timestamp, :payload]
  defstruct [:sequence, :pipeline_id, :type, :timestamp, :status, :payload]

  @attr_keys %{
    "payload" => :payload,
    "sequence" => :sequence,
    "pipeline_id" => :pipeline_id,
    "type" => :type,
    "timestamp" => :timestamp,
    "status" => :status
  }

  @type t :: %__MODULE__{
          sequence: pos_integer(),
          pipeline_id: String.t(),
          type: String.t(),
          timestamp: String.t(),
          status: String.t() | atom() | nil,
          payload: map()
        }

  @spec new(String.t(), pos_integer(), map()) :: t()
  def new(pipeline_id, sequence, payload) when is_binary(pipeline_id) and is_map(payload) do
    normalized_payload =
      payload
      |> Map.put_new("pipeline_id", pipeline_id)
      |> Map.put_new("timestamp", now_iso8601())
      |> Map.put("sequence", sequence)

    %__MODULE__{
      sequence: sequence,
      pipeline_id: pipeline_id,
      type: Map.get(normalized_payload, "type", "message"),
      timestamp: Map.fetch!(normalized_payload, "timestamp"),
      status: Map.get(normalized_payload, "status"),
      payload: normalized_payload
    }
  end

  @spec from_map(map()) :: t()
  def from_map(attrs) when is_map(attrs) do
    payload = payload(attrs)
    sequence = attr(attrs, "sequence") || Map.get(payload, "sequence") || 1
    pipeline_id = attr(attrs, "pipeline_id") || Map.get(payload, "pipeline_id") || ""
    type = attr(attrs, "type") || Map.get(payload, "type") || "message"
    timestamp = attr(attrs, "timestamp") || Map.get(payload, "timestamp") || now_iso8601()
    status = attr(attrs, "status") || Map.get(payload, "status")

    %__MODULE__{
      sequence: sequence,
      pipeline_id: pipeline_id,
      type: type,
      timestamp: timestamp,
      status: status,
      payload:
        payload
        |> Map.put("sequence", sequence)
        |> Map.put("pipeline_id", pipeline_id)
        |> Map.put("type", type)
        |> Map.put("timestamp", timestamp)
        |> maybe_put_status(status)
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event), do: event.payload

  @spec serialize(t()) :: map()
  def serialize(%__MODULE__{} = event) do
    %{
      "sequence" => event.sequence,
      "pipeline_id" => event.pipeline_id,
      "type" => event.type,
      "timestamp" => event.timestamp,
      "status" => event.status,
      "payload" => event.payload
    }
  end

  defp stringify_keys(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end

  defp maybe_put_status(payload, nil), do: payload
  defp maybe_put_status(payload, status), do: Map.put(payload, "status", status)

  defp attr(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Map.get(@attr_keys, key))

  defp payload(attrs) do
    attr(attrs, "payload") ||
      attrs
      |> Map.drop([
        "sequence",
        :sequence,
        "pipeline_id",
        :pipeline_id,
        "type",
        :type,
        "timestamp",
        :timestamp,
        "status",
        :status
      ])
      |> stringify_keys()
  end

  defp now_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
