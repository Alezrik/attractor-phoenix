defmodule AttractorEx.HTTP.Manager do
  @moduledoc false

  use GenServer

  alias AttractorEx

  @terminal_statuses MapSet.new([:success, :fail, :cancelled, "success", "fail", "cancelled"])

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, opts)
  end

  def create_pipeline(server, dot, context, opts \\ []) do
    GenServer.call(server, {:create_pipeline, dot, context, opts}, :infinity)
  end

  def get_pipeline(server, id), do: GenServer.call(server, {:get_pipeline, id})
  def pipeline_graph(server, id), do: GenServer.call(server, {:pipeline_graph, id})
  def pipeline_context(server, id), do: GenServer.call(server, {:pipeline_context, id})
  def pipeline_checkpoint(server, id), do: GenServer.call(server, {:pipeline_checkpoint, id})
  def pipeline_events(server, id), do: GenServer.call(server, {:pipeline_events, id})
  def pending_questions(server, id), do: GenServer.call(server, {:pending_questions, id})

  def submit_answer(server, id, qid, answer),
    do: GenServer.call(server, {:submit_answer, id, qid, answer})

  def subscribe(server, id, pid), do: GenServer.call(server, {:subscribe, id, pid})
  def cancel(server, id), do: GenServer.call(server, {:cancel, id})
  def record_event(server, id, event), do: GenServer.cast(server, {:record_event, id, event})

  def register_question(server, id, question),
    do: GenServer.call(server, {:register_question, id, question})

  def timeout_question(server, id, qid), do: GenServer.cast(server, {:timeout_question, id, qid})

  @impl true
  def init(_state) do
    {:ok, %{pipelines: %{}}}
  end

  @impl true
  def handle_call({:create_pipeline, dot, context, opts}, _from, state) do
    pipeline_id =
      Keyword.get(opts, :pipeline_id, Integer.to_string(System.unique_integer([:positive])))

    logs_root = Keyword.get(opts, :logs_root, Path.join(["tmp", "pipeline_http_runs"]))
    run_opts = Keyword.delete(opts, :pipeline_id)

    pipeline = %{
      id: pipeline_id,
      dot: dot,
      status: :running,
      result: nil,
      error: nil,
      context: normalize_map(context),
      checkpoint: nil,
      events: [],
      questions: %{},
      subscribers: MapSet.new(),
      task_pid: nil,
      logs_root: logs_root
    }

    state = put_in(state, [:pipelines, pipeline_id], pipeline)
    parent = self()

    {:ok, task_pid} =
      Task.start(fn ->
        observer = fn event -> record_event(parent, pipeline_id, event) end

        merged_interviewer_opts =
          run_opts
          |> Keyword.get(:interviewer_opts, [])
          |> Keyword.put(:pipeline_id, pipeline_id)
          |> Keyword.put(:manager, parent)
          |> Keyword.put(:event_observer, observer)

        result =
          AttractorEx.run(dot, context,
            run_id: pipeline_id,
            logs_root: logs_root,
            event_observer: observer,
            interviewer: AttractorEx.Interviewers.Server,
            interviewer_opts: merged_interviewer_opts
          )

        send(parent, {:pipeline_finished, pipeline_id, result})
      end)

    state = put_in(state, [:pipelines, pipeline_id, :task_pid], task_pid)
    {:reply, {:ok, pipeline_id}, state}
  end

  def handle_call({:get_pipeline, id}, _from, state) do
    {:reply, fetch_pipeline(state, id), state}
  end

  def handle_call({:pipeline_graph, id}, _from, state) do
    reply =
      case fetch_pipeline(state, id) do
        {:ok, pipeline} -> {:ok, pipeline.dot}
        error -> error
      end

    {:reply, reply, state}
  end

  def handle_call({:pipeline_context, id}, _from, state) do
    reply =
      case fetch_pipeline(state, id) do
        {:ok, pipeline} -> {:ok, pipeline.context}
        error -> error
      end

    {:reply, reply, state}
  end

  def handle_call({:pipeline_checkpoint, id}, _from, state) do
    reply =
      case fetch_pipeline(state, id) do
        {:ok, pipeline} when is_map(pipeline.checkpoint) -> {:ok, pipeline.checkpoint}
        {:ok, _pipeline} -> {:ok, nil}
        error -> error
      end

    {:reply, reply, state}
  end

  def handle_call({:pipeline_events, id}, _from, state) do
    reply =
      case fetch_pipeline(state, id) do
        {:ok, pipeline} -> {:ok, pipeline.events}
        error -> error
      end

    {:reply, reply, state}
  end

  def handle_call({:pending_questions, id}, _from, state) do
    reply =
      case fetch_pipeline(state, id) do
        {:ok, pipeline} ->
          {:ok, pipeline.questions |> Map.values() |> Enum.sort_by(& &1.id)}

        error ->
          error
      end

    {:reply, reply, state}
  end

  def handle_call({:submit_answer, id, qid, answer}, _from, state) do
    with {:ok, pipeline} <- fetch_pipeline(state, id),
         {:ok, question} <- fetch_question(pipeline, qid) do
      send(question.waiter, {:pipeline_answer, question.ref, answer})
      state = update_in(state, [:pipelines, id, :questions], &Map.delete(&1, qid))
      {:reply, :ok, state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:subscribe, id, pid}, _from, state) do
    case fetch_pipeline(state, id) do
      {:ok, _pipeline} ->
        state = update_in(state, [:pipelines, id, :subscribers], &MapSet.put(&1, pid))
        Process.monitor(pid)
        {:reply, :ok, state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:cancel, id}, _from, state) do
    with {:ok, pipeline} <- fetch_pipeline(state, id) do
      if is_pid(pipeline.task_pid) do
        Process.exit(pipeline.task_pid, :kill)
      end

      event = %{type: "PipelineFailed", status: "cancelled", pipeline_id: id, error: "cancelled"}

      state =
        state
        |> put_in([:pipelines, id, :status], :cancelled)
        |> append_event(id, event)

      {:reply, :ok, state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:register_question, id, question}, _from, state) do
    with {:ok, _pipeline} <- fetch_pipeline(state, id) do
      state = put_in(state, [:pipelines, id, :questions, question.id], question)
      {:reply, :ok, state}
    else
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_cast({:record_event, id, event}, state) do
    {:noreply, append_event(state, id, event)}
  end

  def handle_cast({:timeout_question, id, qid}, state) do
    state =
      update_in(state, [:pipelines, id, :questions], fn questions ->
        Map.delete(questions || %{}, qid)
      end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:pipeline_finished, id, {:ok, result}}, state) do
    status = Map.get(result, :status) || Map.get(result, "status") || :success

    state =
      state
      |> put_in([:pipelines, id, :status], status)
      |> put_in([:pipelines, id, :result], result)
      |> put_in([:pipelines, id, :context], normalize_map(result.context))
      |> put_in([:pipelines, id, :checkpoint], build_checkpoint(result))

    {:noreply, state}
  end

  def handle_info({:pipeline_finished, id, {:error, error}}, state) do
    state =
      state
      |> put_in([:pipelines, id, :status], :fail)
      |> put_in([:pipelines, id, :error], error)

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    pipelines =
      state.pipelines
      |> Enum.map(fn {id, pipeline} ->
        {id, %{pipeline | subscribers: MapSet.delete(pipeline.subscribers, pid)}}
      end)
      |> Map.new()

    {:noreply, %{state | pipelines: pipelines}}
  end

  defp append_event(state, id, event) do
    case get_in(state, [:pipelines, id]) do
      nil ->
        state

      pipeline ->
        normalized_event = normalize_event(id, event)
        notify_subscribers(pipeline.subscribers, normalized_event)

        state
        |> update_in([:pipelines, id, :events], &(&1 ++ [normalized_event]))
        |> maybe_update_checkpoint(id, normalized_event)
        |> maybe_update_context(id, normalized_event)
        |> maybe_update_status(id, normalized_event)
    end
  end

  defp maybe_update_checkpoint(state, id, %{type: "CheckpointSaved", checkpoint: checkpoint}) do
    put_in(state, [:pipelines, id, :checkpoint], checkpoint)
  end

  defp maybe_update_checkpoint(state, _id, _event), do: state

  defp maybe_update_context(state, id, %{context: context}) when is_map(context) do
    put_in(state, [:pipelines, id, :context], normalize_map(context))
  end

  defp maybe_update_context(state, _id, _event), do: state

  defp maybe_update_status(state, id, %{type: "PipelineCompleted"}) do
    put_in(state, [:pipelines, id, :status], :success)
  end

  defp maybe_update_status(state, id, %{type: "PipelineFailed", status: status}) do
    put_in(state, [:pipelines, id, :status], normalize_status(status))
  end

  defp maybe_update_status(state, _id, _event), do: state

  defp notify_subscribers(subscribers, event) do
    Enum.each(subscribers, fn pid -> send(pid, {:pipeline_event, event}) end)
  end

  defp build_checkpoint(result) do
    %{
      "current_node" =>
        List.last(result.history || [])
        |> case do
          %{node_id: node_id} -> node_id
          _ -> nil
        end,
      "completed_nodes" => Map.keys(result.outcomes || %{}),
      "context" => normalize_map(result.context)
    }
  end

  defp normalize_event(id, event) do
    event
    |> normalize_map()
    |> Map.put_new("pipeline_id", id)
    |> Map.put_new(
      "timestamp",
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    )
  end

  defp fetch_pipeline(state, id) do
    case get_in(state, [:pipelines, id]) do
      nil -> {:error, :not_found}
      pipeline -> {:ok, pipeline}
    end
  end

  defp fetch_question(pipeline, qid) do
    case Map.get(pipeline.questions, qid) do
      nil -> {:error, :not_found}
      question -> {:ok, question}
    end
  end

  defp normalize_status(status) do
    if MapSet.member?(@terminal_statuses, status), do: status, else: do_normalize_status(status)
  end

  defp do_normalize_status("cancelled"), do: :cancelled
  defp do_normalize_status("fail"), do: :fail
  defp do_normalize_status("success"), do: :success
  defp do_normalize_status(other), do: other

  defp normalize_map(value) when is_map(value) do
    value
    |> Enum.map(fn {key, item} -> {to_string(key), normalize_map(item)} end)
    |> Map.new()
  end

  defp normalize_map(value) when is_list(value), do: Enum.map(value, &normalize_map/1)
  defp normalize_map(value), do: value
end
