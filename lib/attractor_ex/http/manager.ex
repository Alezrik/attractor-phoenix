defmodule AttractorEx.HTTP.Manager do
  @moduledoc """
  GenServer that owns durable runtime state for HTTP-managed pipeline runs.

  Run metadata, event history, checkpoints, pending questions, and artifact indexes are
  persisted through a pluggable run store so HTTP and Phoenix consumers can replay run
  history after process restarts. The manager also admits one explicit
  checkpoint-backed resume for cancelled runs after the human gate has been fully
  cleared and the accepted answer has been durably recorded.
  """

  use GenServer

  alias AttractorEx

  alias AttractorEx.HTTP.{
    ArtifactRecord,
    CheckpointRecord,
    EventRecord,
    FileRunStore,
    QuestionRecord,
    RunRecord
  }

  @terminal_statuses MapSet.new([:success, :fail, :cancelled, "success", "fail", "cancelled"])

  @doc "Starts the HTTP pipeline manager."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, opts)
  end

  @doc "Creates and starts a pipeline run under HTTP management."
  def create_pipeline(server, dot, context, opts \\ []) do
    GenServer.call(server, {:create_pipeline, dot, context, opts}, :infinity)
  end

  def get_pipeline(server, id), do: GenServer.call(server, {:get_pipeline, id})
  def list_pipelines(server), do: GenServer.call(server, :list_pipelines)
  def pipeline_graph(server, id), do: GenServer.call(server, {:pipeline_graph, id})
  def pipeline_context(server, id), do: GenServer.call(server, {:pipeline_context, id})
  def pipeline_checkpoint(server, id), do: GenServer.call(server, {:pipeline_checkpoint, id})
  def pipeline_events(server, id), do: GenServer.call(server, {:pipeline_events, id})
  def pending_questions(server, id), do: GenServer.call(server, {:pending_questions, id})
  def snapshot(server, id), do: GenServer.call(server, {:snapshot, id})

  @doc "Returns persisted events after the given sequence number."
  def replay_events(server, id, opts \\ []) do
    GenServer.call(server, {:replay_events, id, opts})
  end

  @doc "Clears in-memory and persisted HTTP runtime state for the current manager."
  def reset(server), do: GenServer.call(server, :reset, :infinity)

  @doc "Attempts one explicit checkpoint-backed resume for an admitted interrupted run."
  def resume_pipeline(server, id), do: GenServer.call(server, {:resume_pipeline, id}, :infinity)

  def submit_answer(server, id, qid, answer),
    do: GenServer.call(server, {:submit_answer, id, qid, answer})

  def subscribe(server, id, pid), do: GenServer.call(server, {:subscribe, id, pid})
  def cancel(server, id), do: GenServer.call(server, {:cancel, id})
  def record_event(server, id, event), do: GenServer.cast(server, {:record_event, id, event})

  def register_question(server, id, question),
    do: GenServer.call(server, {:register_question, id, question})

  def timeout_question(server, id, qid), do: GenServer.cast(server, {:timeout_question, id, qid})

  @impl true
  def init(opts) do
    opts = if is_list(opts), do: opts, else: []
    store = Keyword.get(opts, :store, FileRunStore)

    with {:ok, store_config} <- store.init(opts),
         {:ok, pipelines} <- load_pipelines(store, store_config) do
      state = %{
        store: store,
        store_config: store_config,
        pipelines: pipelines
      }

      {:ok, recover_incomplete_runs(state)}
    end
  end

  @impl true
  def handle_call({:create_pipeline, dot, context, opts}, _from, state) do
    pipeline_id =
      Keyword.get(opts, :pipeline_id, Integer.to_string(System.unique_integer([:positive])))

    logs_root = Keyword.get(opts, :logs_root, Path.join(["tmp", "pipeline_http_runs"]))
    execution_opts = Keyword.delete(opts, :pipeline_id)

    run_record = %RunRecord{
      id: pipeline_id,
      dot: dot,
      status: :running,
      result: nil,
      error: nil,
      context: normalize_map(context),
      initial_context: normalize_map(context),
      execution_opts: execution_opts,
      checkpoint: nil,
      logs_root: logs_root,
      inserted_at: now_iso8601(),
      updated_at: now_iso8601(),
      artifacts: ArtifactRecord.index_run_artifacts(logs_root, pipeline_id)
    }

    pipeline =
      build_pipeline(run_record, [], [])
      |> Map.put(:task_pid, nil)

    state = put_in(state, [:pipelines, pipeline_id], pipeline)

    with :ok <- persist_pipeline_record(state, pipeline_id) do
      state = start_run_task(state, pipeline_id, :run)
      {:reply, {:ok, pipeline_id}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:get_pipeline, id}, _from, state) do
    {:reply, fetch_pipeline(state, id), state}
  end

  def handle_call(:list_pipelines, _from, state) do
    pipelines =
      state.pipelines
      |> Map.values()
      |> Enum.sort_by(& &1.inserted_at, :desc)
      |> Enum.map(&pipeline_summary/1)

    {:reply, {:ok, pipelines}, state}
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

  def handle_call({:replay_events, id, opts}, _from, state) do
    reply =
      case fetch_pipeline(state, id) do
        {:ok, _pipeline} ->
          after_sequence = Keyword.get(opts, :after_sequence, 0)
          {:ok, replay_from_memory(state, id, after_sequence)}

        error ->
          error
      end

    {:reply, reply, state}
  end

  def handle_call({:pending_questions, id}, _from, state) do
    reply =
      case fetch_pipeline(state, id) do
        {:ok, pipeline} ->
          {:ok,
           pipeline.questions
           |> Map.values()
           |> Enum.sort_by(& &1.id)
           |> Enum.map(&public_question/1)}

        error ->
          error
      end

    {:reply, reply, state}
  end

  def handle_call({:snapshot, id}, _from, state) do
    reply =
      case fetch_pipeline(state, id) do
        {:ok, pipeline} -> {:ok, pipeline_snapshot(pipeline)}
        error -> error
      end

    {:reply, reply, state}
  end

  def handle_call(:reset, _from, state) do
    stop_pipeline_tasks(state.pipelines)

    with :ok <- clear_store(state.store_config) do
      {:reply, :ok, %{state | pipelines: %{}}}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:submit_answer, id, qid, answer}, _from, state) do
    with {:ok, pipeline} <- fetch_pipeline(state, id),
         {:ok, question} <- fetch_question(pipeline, qid) do
      if is_pid(question.waiter) and is_reference(question.ref) do
        send(question.waiter, {:pipeline_answer, question.ref, answer})
      end

      state =
        state
        |> persist_human_answer(id, qid, answer)
        |> update_in([:pipelines, id, :questions], &Map.delete(&1, qid))
        |> persist_pipeline_questions(id)
        |> notify_question_state(id)

      {:reply, :ok, state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:resume_pipeline, id}, _from, state) do
    with {:ok, pipeline} <- fetch_pipeline(state, id),
         :ok <- validate_resume_contract(pipeline) do
      resumed_from_status = pipeline.status |> normalize_status() |> Atom.to_string()

      state =
        state
        |> put_in([:pipelines, id, :status], :running)
        |> put_in([:pipelines, id, :result], nil)
        |> put_in([:pipelines, id, :error], nil)
        |> touch_pipeline(id)
        |> append_event(id, %{
          type: "PipelineResumeStarted",
          pipeline_id: id,
          status: "running",
          recovery_action: "checkpoint_resume",
          resumed_from_status: resumed_from_status,
          checkpoint: pipeline.checkpoint,
          context: pipeline.context
        })

      state = start_run_task(state, id, :resume)

      {:reply,
       {:ok,
        %{
          "pipeline_id" => id,
          "status" => "running",
          "recovery_action" => "checkpoint_resume",
          "resumed_from_status" => resumed_from_status
        }}, state}
    else
      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}

      {:error, {:resume_unavailable, reason}} ->
        {:reply, {:error, :resume_unavailable, reason}, state}
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
        |> touch_pipeline(id)
        |> append_event(id, event)

      {:reply, :ok, state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:register_question, id, question}, _from, state) do
    with {:ok, _pipeline} <- fetch_pipeline(state, id) do
      question_record = QuestionRecord.from_map(question)

      state =
        state
        |> put_in([:pipelines, id, :questions, question_record.id], question_record)
        |> persist_pipeline_questions(id)
        |> notify_question_state(id)

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
      state
      |> update_in([:pipelines, id, :questions], fn questions ->
        Map.delete(questions || %{}, qid)
      end)
      |> persist_pipeline_questions(id)
      |> notify_question_state(id)

    {:noreply, state}
  end

  @impl true
  def handle_info({:pipeline_finished, id, {:ok, result}}, state) do
    case get_in(state, [:pipelines, id]) do
      nil ->
        {:noreply, state}

      _pipeline ->
        status = Map.get(result, :status) || Map.get(result, "status") || :success

        state =
          state
          |> put_in([:pipelines, id, :status], status)
          |> put_in([:pipelines, id, :result], normalize_map(result))
          |> put_in([:pipelines, id, :error], nil)
          |> put_in([:pipelines, id, :context], normalize_map(result.context))
          |> put_in([:pipelines, id, :checkpoint], build_checkpoint(result))
          |> touch_pipeline(id)
          |> refresh_artifacts(id)

        :ok = persist_pipeline_record(state, id)

        {:noreply, state}
    end
  end

  def handle_info({:pipeline_finished, id, {:error, error}}, state) do
    case get_in(state, [:pipelines, id]) do
      nil ->
        {:noreply, state}

      _pipeline ->
        state =
          state
          |> put_in([:pipelines, id, :status], :fail)
          |> put_in([:pipelines, id, :error], normalize_map(error))
          |> touch_pipeline(id)
          |> refresh_artifacts(id)

        :ok = persist_pipeline_record(state, id)

        {:noreply, state}
    end
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

  defp recover_incomplete_runs(state) do
    Enum.reduce(state.pipelines, state, fn {pipeline_id, pipeline}, acc ->
      if terminal?(pipeline.status) do
        acc
      else
        start_run_task(acc, pipeline_id, recovery_mode(pipeline))
      end
    end)
  end

  defp recovery_mode(%{checkpoint: checkpoint}) when is_map(checkpoint), do: :resume
  defp recovery_mode(_pipeline), do: :run

  defp start_run_task(state, pipeline_id, mode) do
    parent = self()

    {:ok, task_pid} =
      Task.start(fn ->
        observer = fn event -> record_event(parent, pipeline_id, event) end
        pipeline = get_in(state, [:pipelines, pipeline_id])

        run_opts =
          pipeline.execution_opts ++
            [
              run_id: pipeline_id,
              logs_root: pipeline.logs_root,
              event_observer: observer,
              interviewer: AttractorEx.Interviewers.Server,
              interviewer_opts: [
                pipeline_id: pipeline_id,
                manager: parent,
                event_observer: observer
              ]
            ]

        result =
          case mode do
            :resume when is_map(pipeline.checkpoint) ->
              AttractorEx.resume(pipeline.dot, pipeline.checkpoint, run_opts)

            _ ->
              AttractorEx.run(pipeline.dot, pipeline.initial_context, run_opts)
          end

        send(parent, {:pipeline_finished, pipeline_id, result})
      end)

    put_in(state, [:pipelines, pipeline_id, :task_pid], task_pid)
  end

  defp append_event(state, id, event) do
    case get_in(state, [:pipelines, id]) do
      nil ->
        state

      pipeline ->
        sequence = pipeline.next_event_sequence
        normalized_event = normalize_event(id, event, sequence)

        :ok =
          state.store.append_event(state.store_config, id, EventRecord.from_map(normalized_event))

        notify_subscribers(pipeline.subscribers, normalized_event)

        state
        |> touch_pipeline(id)
        |> update_in([:pipelines, id, :events], &(&1 ++ [normalized_event]))
        |> update_in([:pipelines, id, :next_event_sequence], &(&1 + 1))
        |> maybe_update_checkpoint(id, normalized_event)
        |> maybe_update_context(id, normalized_event)
        |> maybe_update_status(id, normalized_event)
        |> refresh_artifacts(id)
        |> then(fn next_state ->
          :ok = persist_pipeline_record(next_state, id)
          next_state
        end)
    end
  end

  defp maybe_update_checkpoint(state, id, %{
         "type" => "CheckpointSaved",
         "checkpoint" => checkpoint
       }) do
    put_in(state, [:pipelines, id, :checkpoint], checkpoint)
  end

  defp maybe_update_checkpoint(state, _id, _event), do: state

  defp maybe_update_context(state, id, %{"context" => context}) when is_map(context) do
    put_in(state, [:pipelines, id, :context], normalize_map(context))
  end

  defp maybe_update_context(state, _id, _event), do: state

  defp maybe_update_status(state, id, %{"type" => "PipelineCompleted"}) do
    put_in(state, [:pipelines, id, :status], :success)
  end

  defp maybe_update_status(state, id, %{"type" => "PipelineFailed", "status" => status}) do
    put_in(state, [:pipelines, id, :status], normalize_status(status))
  end

  defp maybe_update_status(state, _id, _event), do: state

  defp notify_subscribers(subscribers, event) do
    Enum.each(subscribers, fn pid -> send(pid, {:pipeline_event, event}) end)
  end

  defp notify_question_state(state, id) do
    case get_in(state, [:pipelines, id]) do
      nil ->
        state

      pipeline ->
        event =
          normalize_event(
            id,
            %{
              type: "PipelineQuestionsUpdated",
              questions: public_question_payloads(Map.values(pipeline.questions))
            },
            pipeline.next_event_sequence
          )

        :ok = state.store.append_event(state.store_config, id, EventRecord.from_map(event))
        notify_subscribers(pipeline.subscribers, event)

        state
        |> update_in([:pipelines, id, :events], &(&1 ++ [event]))
        |> update_in([:pipelines, id, :next_event_sequence], &(&1 + 1))
        |> touch_pipeline(id)
        |> then(fn next_state ->
          :ok = persist_pipeline_record(next_state, id)
          next_state
        end)
    end
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
      "context" => normalize_map(result.context),
      "timestamp" => now_iso8601()
    }
  end

  defp persist_human_answer(state, id, qid, answer) do
    normalized_answer = normalize_map(answer)

    state
    |> update_in([:pipelines, id, :context], &put_human_answer(&1 || %{}, qid, normalized_answer))
    |> update_in([:pipelines, id, :checkpoint], fn
      nil ->
        nil

      checkpoint ->
        update_in(
          checkpoint,
          ["context"],
          &put_human_answer(normalize_map(&1 || %{}), qid, normalized_answer)
        )
    end)
  end

  defp put_human_answer(context, qid, answer) do
    human =
      context
      |> Map.get("human", %{})
      |> normalize_map()

    answers =
      human
      |> Map.get("answers", %{})
      |> normalize_map()
      |> Map.put(qid, answer)

    context
    |> Map.put("human", Map.put(human, "answers", answers))
  end

  defp normalize_event(id, event, sequence) do
    EventRecord.new(id, sequence, normalize_map(event))
    |> EventRecord.to_map()
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
    do_normalize_status(status)
  end

  defp do_normalize_status(:cancelled), do: :cancelled
  defp do_normalize_status(:fail), do: :fail
  defp do_normalize_status(:success), do: :success
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

  defp pipeline_summary(pipeline) do
    %{
      "pipeline_id" => pipeline.id,
      "status" => pipeline.status,
      "event_count" => length(pipeline.events),
      "pending_questions" => map_size(pipeline.questions),
      "logs_root" => pipeline.logs_root,
      "inserted_at" => pipeline.inserted_at,
      "updated_at" => pipeline.updated_at,
      "has_checkpoint" => is_map(pipeline.checkpoint),
      "resume_ready" => resume_ready?(pipeline),
      "artifacts" => Enum.map(pipeline.artifacts, &ArtifactRecord.to_map/1)
    }
  end

  defp pipeline_snapshot(pipeline) do
    pipeline_summary(pipeline)
    |> Map.merge(%{
      "pipeline_id" => pipeline.id,
      "context" => pipeline.context,
      "checkpoint" => pipeline.checkpoint,
      "questions" => public_questions(Map.values(pipeline.questions)),
      "events" => pipeline.events
    })
  end

  defp public_questions(questions) do
    questions
    |> Enum.sort_by(& &1.id)
    |> Enum.map(&public_question/1)
  end

  defp public_question_payloads(questions) do
    questions
    |> Enum.sort_by(& &1.id)
    |> Enum.map(&public_question_payload/1)
  end

  defp public_question(question) do
    record = QuestionRecord.from_map(question)

    %{
      id: record.id,
      text: record.text,
      type: record.type,
      multiple: record.multiple,
      required: record.required,
      options: record.options,
      timeout_seconds: record.timeout_seconds,
      metadata: record.metadata,
      inserted_at: record.inserted_at
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp public_question_payload(question) do
    question
    |> QuestionRecord.from_map()
    |> QuestionRecord.to_public_map()
  end

  defp touch_pipeline(state, id) do
    put_in(state, [:pipelines, id, :updated_at], now_iso8601())
  end

  defp refresh_artifacts(state, id) do
    case get_in(state, [:pipelines, id]) do
      nil ->
        state

      pipeline ->
        put_in(
          state,
          [:pipelines, id, :artifacts],
          ArtifactRecord.index_run_artifacts(pipeline.logs_root, id)
        )
    end
  end

  defp persist_pipeline_record(state, pipeline_id) do
    case get_in(state, [:pipelines, pipeline_id]) do
      nil ->
        :ok

      pipeline ->
        run_record = %RunRecord{
          id: pipeline.id,
          dot: pipeline.dot,
          status: pipeline.status,
          result: pipeline.result,
          error: pipeline.error,
          context: pipeline.context,
          initial_context: pipeline.initial_context,
          execution_opts: pipeline.execution_opts,
          checkpoint: pipeline.checkpoint && CheckpointRecord.from_map(pipeline.checkpoint),
          logs_root: pipeline.logs_root,
          inserted_at: pipeline.inserted_at,
          updated_at: pipeline.updated_at,
          artifacts: pipeline.artifacts
        }

        :ok = state.store.put_run(state.store_config, run_record)

        :ok =
          state.store.put_questions(
            state.store_config,
            pipeline_id,
            Map.values(pipeline.questions)
          )

        :ok
    end
  end

  defp persist_pipeline_questions(state, id) do
    case get_in(state, [:pipelines, id, :questions]) do
      nil ->
        state

      questions ->
        :ok = state.store.put_questions(state.store_config, id, Map.values(questions))
        state
    end
  end

  defp load_pipelines(store, store_config) do
    with {:ok, loaded_runs} <- store.list_runs(store_config) do
      pipelines =
        loaded_runs
        |> Enum.map(fn %{run: run, events: events, questions: questions} ->
          pipeline = build_pipeline(run, events, questions)
          {pipeline.id, pipeline}
        end)
        |> Map.new()

      {:ok, pipelines}
    end
  end

  defp build_pipeline(run, events, questions) do
    checkpoint = run.checkpoint && CheckpointRecord.to_map(run.checkpoint)
    event_maps = Enum.map(events, &EventRecord.to_map/1)

    %{
      id: run.id,
      dot: run.dot,
      status: normalize_status(run.status),
      result: normalize_map(run.result),
      error: normalize_map(run.error),
      context: normalize_map(run.context),
      initial_context: normalize_map(run.initial_context),
      execution_opts: run.execution_opts || [],
      checkpoint: checkpoint,
      events: event_maps,
      questions: Map.new(questions, &{&1.id, &1}),
      subscribers: MapSet.new(),
      task_pid: nil,
      logs_root: run.logs_root,
      inserted_at: run.inserted_at,
      updated_at: run.updated_at,
      next_event_sequence: next_sequence(event_maps),
      artifacts:
        if(run.artifacts == [] || is_nil(run.artifacts),
          do: ArtifactRecord.index_run_artifacts(run.logs_root, run.id),
          else: run.artifacts
        )
    }
  end

  defp next_sequence([]), do: 1

  defp next_sequence(events) do
    events
    |> List.last()
    |> Map.get("sequence", 0)
    |> Kernel.+(1)
  end

  defp replay_from_memory(state, id, after_sequence) do
    state
    |> get_in([:pipelines, id, :events])
    |> Enum.filter(&(Map.get(&1, "sequence", 0) > after_sequence))
  end

  defp validate_resume_contract(pipeline) do
    cond do
      resume_ready?(pipeline) ->
        :ok

      normalize_status(pipeline.status) != :cancelled ->
        {:error,
         {:resume_unavailable,
          "checkpoint resume is only admitted for the selected cancelled packet"}}

      not is_map(pipeline.checkpoint) ->
        {:error,
         {:resume_unavailable, "checkpoint resume requires a persisted checkpoint snapshot"}}

      map_size(pipeline.questions || %{}) > 0 ->
        {:error,
         {:resume_unavailable,
          "checkpoint resume stays blocked until the selected human gate is fully cleared"}}

      not answered_human_gate?(pipeline) ->
        {:error,
         {:resume_unavailable,
          "checkpoint resume is limited to the post-action cancelled packet with a recorded human answer"}}

      true ->
        {:error, {:resume_unavailable, "checkpoint resume is not available for this run"}}
    end
  end

  defp resume_ready?(pipeline) do
    normalize_status(pipeline.status) == :cancelled and
      is_map(pipeline.checkpoint) and
      map_size(pipeline.questions || %{}) == 0 and
      answered_human_gate?(pipeline)
  end

  defp answered_human_gate?(pipeline) do
    pipeline
    |> human_answers()
    |> map_size()
    |> Kernel.>(0)
  end

  defp human_answers(pipeline) do
    pipeline
    |> checkpoint_or_context()
    |> Map.get("human", %{})
    |> normalize_map()
    |> Map.get("answers", %{})
    |> normalize_map()
  end

  defp checkpoint_or_context(%{checkpoint: %{"context" => checkpoint_context}})
       when is_map(checkpoint_context),
       do: checkpoint_context

  defp checkpoint_or_context(%{context: context}) when is_map(context), do: context
  defp checkpoint_or_context(_pipeline), do: %{}

  defp stop_pipeline_tasks(pipelines) do
    Enum.each(pipelines, fn {_id, pipeline} ->
      case pipeline.task_pid do
        pid when is_pid(pid) -> Process.exit(pid, :kill)
        _ -> :ok
      end
    end)
  end

  defp clear_store(%{root: root}) do
    runs_root = Path.join(root, "runs")

    :ok = remove_path(runs_root)
    File.mkdir_p(runs_root)
  end

  defp clear_store(_store_config), do: :ok

  defp remove_path(path) do
    case File.rm_rf(path) do
      :ok -> :ok
      {:ok, _paths} -> :ok
      {:error, reason, _path} -> {:error, reason}
    end
  end

  defp terminal?(status), do: MapSet.member?(@terminal_statuses, status)

  defp now_iso8601 do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end
end
