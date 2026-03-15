defmodule AttractorEx.HTTP.FileRunStore do
  @moduledoc """
  File-backed durable runtime store for HTTP-managed pipeline runs.

  Each run is persisted under its own directory with:

  - `run.json` for typed run metadata
  - `events.ndjson` for append-only event history
  - `questions.json` for pending question metadata
  """

  @behaviour AttractorEx.HTTP.RunStore

  alias AttractorEx.HTTP.{EventRecord, QuestionRecord, RunRecord}

  @impl true
  def init(opts) do
    root =
      opts
      |> Keyword.get(:store_root, Path.join(["tmp", "attractor_http_store"]))
      |> Path.expand()

    with :ok <- File.mkdir_p(Path.join(root, "runs")) do
      {:ok, %{root: root}}
    end
  end

  @impl true
  def list_runs(config) do
    runs_root = Path.join(config.root, "runs")

    entries =
      case File.ls(runs_root) do
        {:ok, items} -> items
        {:error, :enoent} -> []
        {:error, reason} -> throw({:error, reason})
      end

    loaded =
      entries
      |> Enum.sort()
      |> Enum.reduce([], fn run_id, acc ->
        case load_run(config, run_id) do
          {:ok, loaded_run} -> [loaded_run | acc]
          {:error, :enoent} -> acc
          {:error, reason} -> throw({:error, reason})
        end
      end)
      |> Enum.reverse()

    {:ok, loaded}
  catch
    {:error, reason} -> {:error, reason}
  end

  @impl true
  def put_run(config, %RunRecord{} = run) do
    run_dir = ensure_run_dir(config, run.id)
    write_json(Path.join(run_dir, "run.json"), RunRecord.to_map(run))
  end

  @impl true
  def append_event(config, pipeline_id, %EventRecord{} = event) do
    run_dir = ensure_run_dir(config, pipeline_id)
    encoded = Jason.encode!(EventRecord.serialize(event))
    File.write(Path.join(run_dir, "events.ndjson"), encoded <> "\n", [:append])
  end

  @impl true
  def put_questions(config, pipeline_id, questions) do
    run_dir = ensure_run_dir(config, pipeline_id)

    write_json(
      Path.join(run_dir, "questions.json"),
      Enum.map(questions, &QuestionRecord.serialize/1)
    )
  end

  @impl true
  def list_events(config, pipeline_id, opts \\ []) do
    with {:ok, loaded_run} <- load_run(config, pipeline_id) do
      after_sequence = Keyword.get(opts, :after_sequence, 0)
      {:ok, Enum.filter(loaded_run.events, &(&1.sequence > after_sequence))}
    end
  end

  defp load_run(config, pipeline_id) do
    run_dir = run_dir(config, pipeline_id)

    with {:ok, run_attrs} <- read_json(Path.join(run_dir, "run.json")),
         {:ok, questions_attrs} <- read_json(Path.join(run_dir, "questions.json"), default: []),
         {:ok, events} <- read_events(Path.join(run_dir, "events.ndjson")) do
      {:ok,
       %{
         run: RunRecord.from_map(run_attrs),
         questions: Enum.map(questions_attrs, &QuestionRecord.from_map/1),
         events: events
       }}
    end
  end

  defp read_json(path, opts \\ []) do
    default = Keyword.get(opts, :default, :no_default)

    case File.read(path) do
      {:ok, contents} ->
        Jason.decode(contents)

      {:error, :enoent} when default != :no_default ->
        {:ok, default}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_events(path) do
    case File.read(path) do
      {:ok, contents} ->
        events =
          contents
          |> String.split("\n", trim: true)
          |> Enum.map(fn line -> line |> Jason.decode!() |> EventRecord.from_map() end)

        {:ok, events}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_json(path, value) do
    path
    |> Path.dirname()
    |> File.mkdir_p!()

    encoded = Jason.encode!(value, pretty: true)
    File.write(path, encoded)
  end

  defp ensure_run_dir(config, pipeline_id) do
    dir = run_dir(config, pipeline_id)
    File.mkdir_p!(dir)
    dir
  end

  defp run_dir(config, pipeline_id), do: Path.join([config.root, "runs", pipeline_id])
end
