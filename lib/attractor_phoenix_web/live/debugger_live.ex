defmodule AttractorPhoenixWeb.DebuggerLive do
  use AttractorPhoenixWeb, :live_view

  alias AttractorExPhx
  alias AttractorExPhx.Client, as: AttractorAPI
  alias AttractorPhoenixWeb.OperatorRunData

  @refresh_interval_ms 3_000

  @impl true
  def mount(_params, _session, socket) do
    filters = OperatorRunData.default_debugger_filters()

    socket =
      socket
      |> stream_configure(:questions, dom_id: &"debugger-question-#{&1["id"]}")
      |> stream_configure(:timeline_events, dom_id: &timeline_event_dom_id/1)
      |> assign(
        page_title: "Run Debugger",
        run_id: nil,
        filters: filters,
        filter_form: to_form(filters, as: :filters),
        selected_event_sequence: nil,
        selected_pipeline: nil,
        selected_status_alias: nil,
        selected_context: %{},
        selected_checkpoint: nil,
        selected_questions: [],
        question_lookup: %{},
        answer_forms: %{},
        last_question_receipt: nil,
        last_recovery_receipt: nil,
        all_events: [],
        filtered_events: [],
        selected_event: nil,
        event_filter_options: %{types: [], statuses: [], nodes: []},
        context_diff: %{entries: [], counts: %{changed: 0, added: 0, removed: 0}},
        connection_state: if(connected?(socket), do: :live, else: :idle),
        update_mode: :subscription,
        error: nil,
        last_updated_at: nil,
        subscribed_pipeline_id: nil
      )
      |> stream(:questions, [], reset: true)
      |> stream(:timeline_events, [], reset: true)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => run_id} = params, _uri, socket) do
    filters = OperatorRunData.debugger_filters_from_params(params)

    socket =
      socket
      |> assign(
        run_id: run_id,
        filters: filters,
        filter_form: to_form(filters, as: :filters),
        selected_event_sequence: params["event"],
        last_question_receipt: nil,
        last_recovery_receipt: nil
      )
      |> refresh_run()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_debugger", %{"filters" => params}, socket) do
    filters =
      socket.assigns.filters
      |> Map.merge(Map.take(params, ["type", "status", "node", "search", "focus"]))

    {:noreply,
     push_patch(
       socket,
       to:
         ~p"/runs/#{socket.assigns.run_id}/debugger?#{OperatorRunData.debugger_query_params(filters)}"
     )}
  end

  def handle_event("clear_debugger_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/runs/#{socket.assigns.run_id}/debugger")}
  end

  def handle_event("select_event", %{"sequence" => sequence}, socket) do
    {:noreply,
     push_patch(
       socket,
       to:
         ~p"/runs/#{socket.assigns.run_id}/debugger?#{OperatorRunData.debugger_query_params(socket.assigns.filters, sequence)}"
     )}
  end

  def handle_event("cancel_pipeline", _params, %{assigns: %{run_id: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_pipeline", _params, socket) do
    socket =
      case AttractorAPI.cancel_pipeline(socket.assigns.run_id) do
        {:ok, _payload} -> refresh_run(socket)
        {:error, message} -> assign(socket, error: message)
      end

    {:noreply, socket}
  end

  def handle_event("resume_pipeline", _params, %{assigns: %{run_id: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("resume_pipeline", _params, socket) do
    socket =
      case AttractorAPI.resume_pipeline(socket.assigns.run_id) do
        {:ok, _payload} ->
          socket
          |> refresh_run()
          |> assign(last_recovery_receipt: OperatorRunData.recovery_resume_receipt(), error: nil)

        {:error, message} ->
          assign(socket, error: message)
      end

    {:noreply, socket}
  end

  def handle_event(
        "answer_question",
        %{"question_id" => question_id, "response" => response},
        socket
      ) do
    question = Map.get(socket.assigns.question_lookup, question_id)
    answer = OperatorRunData.build_question_answer(question, response || %{})

    socket =
      case AttractorAPI.answer_question(socket.assigns.run_id, question_id, answer) do
        {:ok, _payload} ->
          refreshed_socket = refresh_run(socket)

          assign(
            refreshed_socket,
            :last_question_receipt,
            OperatorRunData.question_resolution_summary(
              question,
              refreshed_socket.assigns.selected_pipeline,
              refreshed_socket.assigns.selected_questions
            )
          )

        {:error, message} ->
          assign(socket, error: message)
      end

    {:noreply, socket}
  end

  def handle_event("operator_connection_state", %{"state" => state}, socket) do
    socket =
      case state do
        "live" ->
          socket
          |> assign(connection_state: live_connection_state(socket.assigns.update_mode))
          |> maybe_restore_live_updates()

        "reconnecting" ->
          assign(socket, connection_state: :reconnecting)

        _ ->
          socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:attractor_ex_event, %{"pipeline_id" => pipeline_id}},
        %{assigns: %{run_id: pipeline_id, update_mode: :subscription}} = socket
      ) do
    {:noreply, refresh_run(socket)}
  end

  def handle_info({:attractor_ex_event, _event}, socket), do: {:noreply, socket}

  def handle_info(:poll_run, %{assigns: %{update_mode: :polling}} = socket) do
    socket =
      socket
      |> refresh_run()
      |> schedule_poll()

    {:noreply, socket}
  end

  def handle_info(:poll_run, socket), do: {:noreply, socket}

  defp refresh_run(%{assigns: %{run_id: nil}} = socket), do: socket

  defp refresh_run(socket) do
    case OperatorRunData.load_run(socket.assigns.run_id) do
      {:ok, detail} ->
        events = OperatorRunData.timeline_events(detail.events)
        filtered_events = OperatorRunData.filter_events(events, socket.assigns.filters)

        selected_event =
          OperatorRunData.find_event(filtered_events, socket.assigns.selected_event_sequence)

        questions = detail.questions

        socket
        |> assign(
          selected_pipeline: detail.summary,
          selected_status_alias: detail.status_alias,
          selected_context: detail.context,
          selected_checkpoint: detail.checkpoint,
          selected_questions: questions,
          question_lookup: Map.new(questions, &{&1["id"], &1}),
          answer_forms: detail.answer_forms,
          all_events: events,
          filtered_events: filtered_events,
          selected_event: selected_event,
          selected_event_sequence:
            if(selected_event, do: OperatorRunData.event_sequence(selected_event), else: nil),
          event_filter_options: OperatorRunData.event_filter_options(events),
          context_diff:
            OperatorRunData.context_checkpoint_diff(detail.context, detail.checkpoint),
          error: nil,
          last_updated_at: DateTime.utc_now()
        )
        |> stream(:questions, questions, reset: true)
        |> stream(:timeline_events, filtered_events, reset: true)
        |> ensure_subscription()

      {:error, message} ->
        socket
        |> assign(
          error: message,
          selected_pipeline: nil,
          all_events: [],
          filtered_events: [],
          selected_event: nil,
          context_diff: %{entries: [], counts: %{changed: 0, added: 0, removed: 0}}
        )
        |> stream(:questions, [], reset: true)
        |> stream(:timeline_events, [], reset: true)
    end
  end

  defp ensure_subscription(socket) do
    if connected?(socket) and socket.assigns.update_mode == :subscription do
      case maybe_subscribe(socket.assigns.run_id, socket.assigns.subscribed_pipeline_id) do
        :ok ->
          assign(socket,
            subscribed_pipeline_id: socket.assigns.run_id,
            connection_state: :live
          )

        {:error, _reason} ->
          socket
          |> assign(update_mode: :polling, connection_state: :stale)
          |> schedule_poll()
      end
    else
      socket
    end
  end

  defp maybe_subscribe(run_id, run_id), do: :ok

  defp maybe_subscribe(run_id, previous_run_id) do
    if is_binary(previous_run_id) do
      AttractorExPhx.unsubscribe_pipeline(previous_run_id)
    end

    case AttractorExPhx.subscribe_pipeline(run_id) do
      {:ok, _snapshot} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_restore_live_updates(%{assigns: %{update_mode: :subscription}} = socket), do: socket

  defp maybe_restore_live_updates(socket) do
    socket
    |> assign(update_mode: :subscription, error: nil)
    |> refresh_run()
  end

  defp schedule_poll(socket) do
    Process.send_after(self(), :poll_run, @refresh_interval_ms)
    socket
  end

  defp live_connection_state(:subscription), do: :live
  defp live_connection_state(:polling), do: :stale

  defp timeline_event_dom_id(event) do
    "timeline-event-#{OperatorRunData.event_sequence(event)}"
  end
end
