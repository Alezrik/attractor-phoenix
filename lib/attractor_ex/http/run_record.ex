defmodule AttractorEx.HTTP.RunRecord do
  @moduledoc """
  Typed persisted pipeline run metadata for the HTTP runtime.
  """

  alias AttractorEx.HTTP.{ArtifactRecord, CheckpointRecord}

  @attr_keys %{
    "id" => :id,
    "dot" => :dot,
    "status" => :status,
    "result" => :result,
    "error" => :error,
    "context" => :context,
    "initial_context" => :initial_context,
    "execution_opts" => :execution_opts,
    "checkpoint" => :checkpoint,
    "logs_root" => :logs_root,
    "inserted_at" => :inserted_at,
    "updated_at" => :updated_at,
    "artifacts" => :artifacts
  }

  @enforce_keys [
    :id,
    :dot,
    :status,
    :context,
    :initial_context,
    :logs_root,
    :inserted_at,
    :updated_at
  ]
  defstruct [
    :id,
    :dot,
    :status,
    :result,
    :error,
    :context,
    :initial_context,
    :execution_opts,
    :checkpoint,
    :logs_root,
    :inserted_at,
    :updated_at,
    :artifacts
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          dot: String.t(),
          status: atom() | String.t(),
          result: map() | nil,
          error: term(),
          context: map(),
          initial_context: map(),
          execution_opts: keyword(),
          checkpoint: CheckpointRecord.t() | nil,
          logs_root: String.t(),
          inserted_at: String.t(),
          updated_at: String.t(),
          artifacts: [ArtifactRecord.t()]
        }

  @spec from_map(map()) :: t()
  def from_map(attrs) when is_map(attrs) do
    now = now_iso8601()

    %__MODULE__{
      id: attr(attrs, "id"),
      dot: attr(attrs, "dot", ""),
      status: attr(attrs, "status", :running),
      result: attr(attrs, "result"),
      error: attr(attrs, "error"),
      context: attr(attrs, "context", %{}),
      initial_context: attr(attrs, "initial_context", %{}),
      execution_opts: execution_opts(attrs),
      checkpoint: checkpoint(attrs),
      logs_root: attr(attrs, "logs_root", Path.join(["tmp", "pipeline_http_runs"])),
      inserted_at: attr(attrs, "inserted_at", now),
      updated_at: attr(attrs, "updated_at", now),
      artifacts: artifacts(attrs)
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = run) do
    %{
      "id" => run.id,
      "dot" => run.dot,
      "status" => run.status,
      "result" => run.result,
      "error" => run.error,
      "context" => run.context,
      "initial_context" => run.initial_context,
      "execution_opts" =>
        Enum.into(run.execution_opts || [], %{}, fn {key, value} -> {to_string(key), value} end),
      "checkpoint" => run.checkpoint && CheckpointRecord.to_map(run.checkpoint),
      "logs_root" => run.logs_root,
      "inserted_at" => run.inserted_at,
      "updated_at" => run.updated_at,
      "artifacts" => Enum.map(run.artifacts || [], &ArtifactRecord.to_map/1)
    }
  end

  defp now_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp execution_opt_key("max_steps"), do: :max_steps
  defp execution_opt_key("logs_root"), do: :logs_root
  defp execution_opt_key("retry_sleep"), do: :retry_sleep
  defp execution_opt_key("initial_delay_ms"), do: :initial_delay_ms
  defp execution_opt_key("backoff_factor"), do: :backoff_factor
  defp execution_opt_key("max_delay_ms"), do: :max_delay_ms
  defp execution_opt_key("retry_jitter"), do: :retry_jitter
  defp execution_opt_key("pipeline_id"), do: :pipeline_id
  defp execution_opt_key(_key), do: nil

  defp attr(attrs, key, default \\ nil) do
    Map.get(attrs, key) || Map.get(attrs, Map.get(@attr_keys, key)) || default
  end

  defp execution_opts(attrs) do
    attrs
    |> attr("execution_opts", [])
    |> Enum.reduce([], fn
      {key, value}, acc when is_binary(key) ->
        case execution_opt_key(key) do
          nil -> acc
          atom_key -> [{atom_key, value} | acc]
        end

      {key, value}, acc ->
        [{key, value} | acc]
    end)
    |> Enum.reverse()
  end

  defp checkpoint(attrs) do
    case attr(attrs, "checkpoint") do
      nil -> nil
      checkpoint -> CheckpointRecord.from_map(checkpoint)
    end
  end

  defp artifacts(attrs) do
    attrs
    |> attr("artifacts", [])
    |> Enum.map(&ArtifactRecord.from_map/1)
  end
end
