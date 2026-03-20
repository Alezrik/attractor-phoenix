defmodule AttractorPhoenix.PipelineLibrary do
  @moduledoc """
  File-backed storage for reusable builder pipelines.

  Entries are persisted as JSON so the builder and `/library` LiveViews can
  share saved DOT graphs without introducing a database dependency.
  """

  use GenServer

  @type entry :: %{
          id: String.t(),
          name: String.t(),
          description: String.t(),
          dot: String.t(),
          context_json: String.t(),
          inserted_at: String.t(),
          updated_at: String.t()
        }

  @type attrs :: %{
          optional(String.t()) => String.t() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec list_entries() :: [entry()]
  def list_entries do
    GenServer.call(__MODULE__, :list_entries)
  end

  @spec get_entry(String.t()) :: {:ok, entry()} | {:error, :not_found}
  def get_entry(id) when is_binary(id) do
    GenServer.call(__MODULE__, {:get_entry, id})
  end

  @spec create_entry(attrs()) :: {:ok, entry()} | {:error, map()}
  def create_entry(attrs) when is_map(attrs) do
    GenServer.call(__MODULE__, {:create_entry, attrs})
  end

  @spec update_entry(String.t(), attrs()) :: {:ok, entry()} | {:error, :not_found | map()}
  def update_entry(id, attrs) when is_binary(id) and is_map(attrs) do
    GenServer.call(__MODULE__, {:update_entry, id, attrs})
  end

  @spec delete_entry(String.t()) :: :ok | {:error, :not_found}
  def delete_entry(id) when is_binary(id) do
    GenServer.call(__MODULE__, {:delete_entry, id})
  end

  @spec reset() :: :ok
  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(opts) do
    path = Keyword.get(opts, :path, storage_path())

    state = %{
      path: path,
      entries: load_entries(path)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:list_entries, _from, state) do
    {:reply, sort_entries(state.entries), state}
  end

  def handle_call({:get_entry, id}, _from, state) do
    reply =
      case Map.fetch(state.entries, id) do
        {:ok, entry} -> {:ok, entry}
        :error -> {:error, :not_found}
      end

    {:reply, reply, state}
  end

  def handle_call({:create_entry, attrs}, _from, state) do
    with {:ok, entry} <- build_new_entry(attrs, state.entries),
         {:ok, next_state} <-
           persist_entries(%{state | entries: Map.put(state.entries, entry.id, entry)}) do
      {:reply, {:ok, entry}, next_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:update_entry, id, attrs}, _from, state) do
    with {:ok, existing} <- fetch_existing(state.entries, id),
         {:ok, entry} <- build_updated_entry(existing, attrs),
         {:ok, next_state} <-
           persist_entries(%{state | entries: Map.put(state.entries, id, entry)}) do
      {:reply, {:ok, entry}, next_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:delete_entry, id}, _from, state) do
    case Map.has_key?(state.entries, id) do
      true ->
        entries = Map.delete(state.entries, id)

        case persist_entries(%{state | entries: entries}) do
          {:ok, next_state} -> {:reply, :ok, next_state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end

      false ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:reset, _from, state) do
    case persist_entries(%{state | entries: %{}}) do
      {:ok, next_state} -> {:reply, :ok, next_state}
      {:error, _reason} -> {:reply, :ok, %{state | entries: %{}}}
    end
  end

  defp storage_path do
    Application.get_env(
      :attractor_phoenix,
      :pipeline_library_path,
      Path.expand("../tmp/pipeline_library.json", __DIR__)
    )
  end

  defp fetch_existing(entries, id) do
    case Map.fetch(entries, id) do
      {:ok, entry} -> {:ok, entry}
      :error -> {:error, :not_found}
    end
  end

  defp build_new_entry(attrs, entries) do
    with {:ok, normalized} <- normalize_attrs(attrs),
         {:ok, id} <- generate_unique_id(normalized, entries) do
      timestamp = timestamp()

      {:ok,
       %{
         id: id,
         name: normalized.name,
         description: normalized.description,
         dot: normalized.dot,
         context_json: normalized.context_json,
         inserted_at: timestamp,
         updated_at: timestamp
       }}
    end
  end

  defp build_updated_entry(existing, attrs) do
    with {:ok, normalized} <- normalize_attrs(attrs) do
      {:ok,
       %{
         existing
         | name: normalized.name,
           description: normalized.description,
           dot: normalized.dot,
           context_json: normalized.context_json,
           updated_at: timestamp()
       }}
    end
  end

  defp normalize_attrs(attrs) do
    name = attrs |> Map.get("name", "") |> to_string() |> String.trim()
    description = attrs |> Map.get("description", "") |> to_string() |> String.trim()
    dot = attrs |> Map.get("dot", "") |> to_string() |> String.trim()
    context_json = attrs |> Map.get("context_json", "{}") |> to_string() |> String.trim()

    cond do
      name == "" ->
        {:error, %{field: :name, message: "Name is required."}}

      dot == "" ->
        {:error, %{field: :dot, message: "DOT source is required."}}

      true ->
        validate_context_json(name, description, dot, context_json)
    end
  end

  defp validate_context_json(name, description, dot, context_json) do
    case Jason.decode(context_json) do
      {:ok, context} when is_map(context) ->
        {:ok,
         %{
           name: name,
           description: description,
           dot: dot,
           context_json: Jason.encode_to_iodata!(context, pretty: true) |> IO.iodata_to_binary()
         }}

      {:ok, _value} ->
        {:error, %{field: :context_json, message: "Context JSON must be an object."}}

      {:error, error} ->
        {:error,
         %{field: :context_json, message: "Context JSON is invalid: #{Exception.message(error)}"}}
    end
  end

  defp generate_unique_id(%{name: name}, entries) do
    base_id =
      name
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")

    id = if base_id == "", do: "pipeline", else: base_id

    if Map.has_key?(entries, id) do
      {:error,
       %{
         field: :name,
         message: "A library pipeline with this name already exists. Rename it first."
       }}
    else
      {:ok, id}
    end
  end

  defp persist_entries(state) do
    payload = Jason.encode_to_iodata!(sort_entries(state.entries), pretty: true)
    path = state.path
    tmp_path = path <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(tmp_path, payload),
         :ok <- File.rename(tmp_path, path) do
      {:ok, state}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_entries(path) do
    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, entries} when is_list(entries) ->
            Map.new(entries, fn entry ->
              normalized = normalize_loaded_entry(entry)
              {normalized.id, normalized}
            end)

          _ ->
            %{}
        end

      {:error, :enoent} ->
        %{}

      {:error, _reason} ->
        %{}
    end
  end

  defp normalize_loaded_entry(entry) do
    %{
      id: Map.get(entry, "id", "pipeline"),
      name: Map.get(entry, "name", "Pipeline"),
      description: Map.get(entry, "description", ""),
      dot: Map.get(entry, "dot", ""),
      context_json: Map.get(entry, "context_json", "{}"),
      inserted_at: Map.get(entry, "inserted_at", timestamp()),
      updated_at: Map.get(entry, "updated_at", timestamp())
    }
  end

  defp sort_entries(entries) when is_map(entries) do
    entries
    |> Map.values()
    |> Enum.sort(fn left, right ->
      case DateTime.compare(parse_timestamp(left.updated_at), parse_timestamp(right.updated_at)) do
        :eq -> left.name <= right.name
        :gt -> true
        :lt -> false
      end
    end)
  end

  defp timestamp do
    DateTime.utc_now() |> DateTime.truncate(:microsecond) |> DateTime.to_iso8601()
  end

  defp parse_timestamp(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> ~U[1970-01-01 00:00:00Z]
    end
  end
end
