defmodule AttractorEx.HTTP.ArtifactRecord do
  @moduledoc """
  Typed artifact metadata for persisted HTTP-managed pipeline runs.
  """

  @enforce_keys [:path, :kind, :size, :updated_at]
  defstruct [:path, :kind, :size, :updated_at]

  @type t :: %__MODULE__{
          path: String.t(),
          kind: String.t(),
          size: non_neg_integer(),
          updated_at: String.t()
        }

  @spec index_run_artifacts(String.t(), String.t()) :: [t()]
  def index_run_artifacts(logs_root, pipeline_id)
      when is_binary(logs_root) and is_binary(pipeline_id) do
    run_root = Path.join(logs_root, pipeline_id)

    if File.dir?(run_root) do
      run_root
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&from_path(run_root, &1))
      |> Enum.sort_by(& &1.path)
    else
      []
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = artifact) do
    %{
      "path" => artifact.path,
      "kind" => artifact.kind,
      "size" => artifact.size,
      "updated_at" => artifact.updated_at
    }
  end

  @spec from_map(map()) :: t()
  def from_map(attrs) when is_map(attrs) do
    %__MODULE__{
      path: Map.get(attrs, "path") || Map.get(attrs, :path) || "",
      kind: Map.get(attrs, "kind") || Map.get(attrs, :kind) || "file",
      size: Map.get(attrs, "size") || Map.get(attrs, :size) || 0,
      updated_at:
        Map.get(attrs, "updated_at") || Map.get(attrs, :updated_at) ||
          DateTime.utc_now() |> iso8601()
    }
  end

  defp from_path(run_root, path) do
    stat = File.stat!(path, time: :posix)

    %__MODULE__{
      path: Path.relative_to(path, run_root),
      kind: artifact_kind(path),
      size: stat.size,
      updated_at: stat.mtime |> DateTime.from_unix!(:second) |> iso8601()
    }
  end

  defp artifact_kind(path) do
    case Path.extname(path) do
      ".json" -> "json"
      ".log" -> "log"
      ".txt" -> "text"
      ".dot" -> "graphviz"
      _ -> "file"
    end
  end

  defp iso8601(datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
