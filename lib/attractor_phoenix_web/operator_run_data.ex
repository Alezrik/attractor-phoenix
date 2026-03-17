defmodule AttractorPhoenixWeb.OperatorRunData do
  @moduledoc false

  alias AttractorExPhx.Client, as: AttractorAPI
  alias Phoenix.HTML

  @terminal_statuses MapSet.new([:success, :fail, :cancelled, "success", "fail", "cancelled"])

  def list_pipelines do
    AttractorAPI.list_pipelines()
  end

  def load_run(pipeline_id) when is_binary(pipeline_id) do
    with {:ok, summary} <- AttractorAPI.get_pipeline(pipeline_id),
         {:ok, status_alias} <- AttractorAPI.get_status(pipeline_id),
         {:ok, context_payload} <- AttractorAPI.get_pipeline_context(pipeline_id),
         {:ok, checkpoint_payload} <- AttractorAPI.get_pipeline_checkpoint(pipeline_id),
         {:ok, questions_payload} <- AttractorAPI.get_pipeline_questions(pipeline_id),
         {:ok, events_payload} <- AttractorAPI.get_pipeline_events(pipeline_id),
         {:ok, graph_svg} <- AttractorAPI.get_pipeline_graph_svg(pipeline_id),
         {:ok, graph_json} <- AttractorAPI.get_pipeline_graph_json(pipeline_id),
         {:ok, graph_dot} <- AttractorAPI.get_pipeline_graph_dot(pipeline_id),
         {:ok, graph_mermaid} <- AttractorAPI.get_pipeline_graph_mermaid(pipeline_id),
         {:ok, graph_text} <- AttractorAPI.get_pipeline_graph_text(pipeline_id) do
      questions = questions_payload["questions"] || []
      events = events_payload["events"] || []

      {:ok,
       %{
         summary: summary,
         status_alias: status_alias,
         context: context_payload["context"] || %{},
         checkpoint: checkpoint_payload["checkpoint"],
         questions: questions,
         answer_forms: build_answer_forms(questions),
         events: events,
         graphs: %{
           "svg" => graph_svg,
           "json" => graph_json["graph"] || %{},
           "dot" => graph_dot,
           "mermaid" => graph_mermaid,
           "text" => graph_text
         }
       }}
    end
  end

  def summarize_pipelines(pipelines) do
    counts =
      Enum.reduce(
        pipelines,
        %{running: 0, success: 0, fail: 0, cancelled: 0, questions: 0},
        fn pipeline, acc ->
          status = normalize_status(pipeline["status"])

          acc
          |> Map.update(status, 1, &(&1 + 1))
          |> Map.update(
            :questions,
            pipeline["pending_questions"] || 0,
            &(&1 + (pipeline["pending_questions"] || 0))
          )
        end
      )

    %{
      total_pipelines: length(pipelines),
      running_pipelines: counts.running,
      successful_pipelines: counts.success,
      failed_pipelines: counts.fail,
      cancelled_pipelines: counts.cancelled,
      total_questions: counts.questions
    }
  end

  def terminal_status?(status), do: MapSet.member?(@terminal_statuses, status)

  def normalize_status(status) when status in [:success, "success"], do: :success
  def normalize_status(status) when status in [:fail, "fail"], do: :fail
  def normalize_status(status) when status in [:cancelled, "cancelled"], do: :cancelled
  def normalize_status(_status), do: :running

  def status_tone(status) do
    case normalize_status(status) do
      :success -> "run-status-success"
      :fail -> "run-status-fail"
      :cancelled -> "run-status-cancelled"
      :running -> "run-status-running"
    end
  end

  def failure_review_signal(pipeline) do
    summary = recovery_summary(pipeline)

    %{
      label: summary.label,
      detail: summary.detail,
      tone: summary.tone
    }
  end

  def run_state_label(pipeline) do
    status = normalize_status(pipeline["status"])
    pending_questions = pipeline["pending_questions"] || 0

    cond do
      pending_questions > 0 -> "Awaiting human action"
      status == :fail -> "Failed"
      status == :cancelled -> "Interrupted"
      status == :success -> "Completed"
      true -> "Running"
    end
  end

  def run_state_detail(pipeline) do
    status = normalize_status(pipeline["status"])
    pending_questions = pipeline["pending_questions"] || 0
    has_checkpoint = pipeline["has_checkpoint"] == true

    cond do
      pending_questions > 0 ->
        "#{pending_questions} pending question(s) still block this run, so operator input is required before progress can continue."

      status == :fail and has_checkpoint ->
        "The run is in failed state, but a checkpoint snapshot is available for comparison before any recovery decision."

      status == :fail ->
        "The run is in failed state without a surfaced checkpoint snapshot, so diagnosis should start from the latest run and debugger evidence."

      status == :cancelled and has_checkpoint ->
        "The run ended in cancelled state after checkpointable progress, so operators can inspect the saved boundary before deciding next steps."

      status == :cancelled ->
        "The run ended in cancelled state without a surfaced checkpoint snapshot."

      status == :success ->
        "The run completed successfully and no operator action is currently required."

      true ->
        "The run is still active, so state and recent events should be monitored before intervention."
    end
  end

  def recovery_summary(pipeline, questions \\ [])

  def recovery_summary(nil, _questions), do: nil

  def recovery_summary(pipeline, questions) do
    status = normalize_status(pipeline["status"])
    pending_questions = max(pipeline["pending_questions"] || 0, length(questions))
    has_checkpoint = pipeline["has_checkpoint"] == true
    first_question = List.first(questions)

    cond do
      pending_questions > 0 ->
        %{
          label: "Human gate blocks progress",
          tone: "run-status-question",
          mode: "Action-taking route",
          owner: "Operator review required",
          action:
            if(is_map(first_question),
              do: question_prompt(first_question),
              else: "Answer pending human gate"
            ),
          detail:
            "#{pending_questions} pending question(s) still block the run, so the truthful recovery path starts with a human answer rather than automatic retry or resume.",
          next_step:
            if is_map(first_question) do
              "Answer the pending question on this route or inspect the debugger before responding."
            else
              "Open run detail or debugger to inspect the waiting prompt before responding."
            end,
          effect:
            "Submitting an answer advances the waiting gate. It does not retry, replay, or resume the run by itself.",
          unavailable:
            "Retry, replay, and resume are not exposed as safe operator actions on this route yet."
        }

      status == :fail and has_checkpoint ->
        %{
          label: "Failure with checkpoint context",
          tone: "run-status-fail",
          mode: "Inspection-first route",
          owner: "Operator diagnosis",
          action: "Compare checkpoint and failure timeline",
          detail:
            "The run failed after checkpointable progress, so the truthful next step is debugger inspection before any recovery claim.",
          next_step:
            "Inspect the debugger timeline and checkpoint diff before planning any restart or resume work.",
          effect:
            "Checkpoint inspection helps compare the last saved state against the failure path. It does not resume the run from this route.",
          unavailable: "Resume, retry, and replay are not exposed here as safe operator actions."
        }

      status == :fail ->
        %{
          label: "Failure without checkpoint context",
          tone: "run-status-fail",
          mode: "Inspection-first route",
          owner: "Operator diagnosis",
          action: "Inspect latest failure events",
          detail:
            "The run failed without a surfaced checkpoint snapshot, so the truthful next step is event-level diagnosis rather than recovery promises.",
          next_step:
            "Open run detail or debugger and inspect the latest failure events before deciding follow-up.",
          effect:
            "Inspection clarifies where the run failed. It does not unlock retry, replay, or resume from this route.",
          unavailable:
            "Retry, replay, and resume remain unavailable until a stronger runtime-safe recovery path exists."
        }

      status == :cancelled and has_checkpoint ->
        %{
          label: "Interrupted with checkpoint context",
          tone: "run-status-cancelled",
          mode: "Inspection and planning route",
          owner: "Operator decision",
          action: "Inspect checkpoint boundary",
          detail:
            "The run ended in cancelled state after checkpointable progress, so operators can inspect the saved boundary before deciding what work to restart elsewhere.",
          next_step:
            "Use the debugger to compare the checkpoint snapshot and recent events before planning recovery.",
          effect:
            "Checkpoint comparison supports recovery planning. It does not resume the cancelled run from this route.",
          unavailable: "Resume, retry, and replay are not exposed here as safe operator actions."
        }

      status == :cancelled ->
        %{
          label: "Interrupted without checkpoint context",
          tone: "run-status-cancelled",
          mode: "Inspection-only route",
          owner: "Operator decision",
          action: "Inspect interruption timeline",
          detail:
            "The run ended in cancelled state without a surfaced checkpoint snapshot, so the truthful next step is timeline inspection.",
          next_step:
            "Inspect recent events and failure context before deciding whether to rerun work outside this route.",
          effect:
            "Timeline inspection explains where work stopped. It does not reopen the cancelled run.",
          unavailable: "Resume, retry, and replay are not exposed here as safe operator actions."
        }

      status == :success ->
        %{
          label: "Completed without recovery work",
          tone: "run-status-success",
          mode: "Inspection-only route",
          owner: "No operator action required",
          action: "Review run artifacts only",
          detail:
            "The run completed successfully, so this route is for inspection and audit rather than recovery.",
          next_step:
            "Review artifacts, context, or timeline only if deeper inspection is needed.",
          effect:
            "Inspection preserves context. No state-changing recovery action is required from this route.",
          unavailable: "Recovery controls are not exposed for completed runs."
        }

      true ->
        %{
          label: "Active run under observation",
          tone: "run-status-running",
          mode: "Observation with stop control",
          owner: "Operator monitoring",
          action: "Monitor state and stop only if necessary",
          detail:
            "The run is still active, so the truthful next step is observation unless the operator needs to halt execution.",
          next_step:
            "Monitor recent events and current state. Use cancel only when the current run should stop.",
          effect:
            "Cancel stops further execution and moves the run into cancelled state. It does not preserve a new recovery checkpoint by itself.",
          unavailable: "Resume, retry, and replay are not exposed here while the run is active."
        }
    end
  end

  def cancel_action_detail(nil), do: "Cancel is unavailable until a run is loaded."

  def cancel_action_detail(pipeline) do
    if terminal_status?(pipeline["status"]) do
      "Cancel is disabled because the run is already terminal. Use this route for inspection, not further state changes."
    else
      "Cancel is the only state-changing control on this route. It stops active work and does not answer a human gate or resume from checkpoint."
    end
  end

  def latest_update_summary([]), do: "Waiting for runtime events"

  def latest_update_summary(events) do
    event = List.first(recent_events(events, 1))

    case event do
      nil ->
        "Waiting for runtime events"

      event ->
        [
          event_summary(event),
          event_timestamp(event)
        ]
        |> Enum.reject(&blank?/1)
        |> Enum.join(" at ")
    end
  end

  def checkpoint_summary(nil), do: "No checkpoint published"

  def checkpoint_summary(checkpoint) do
    node =
      checkpoint["current_node"] ||
        get_in(checkpoint, ["context", "current_node"]) ||
        checkpoint["node_id"]

    if blank?(node), do: "Checkpoint available", else: "Checkpoint at #{node}"
  end

  def checkpoint_detail(nil),
    do: "No checkpoint snapshot is currently advertised for this run."

  def checkpoint_detail(checkpoint) do
    inserted_at = checkpoint["inserted_at"] || checkpoint["timestamp"]

    cond do
      present?(inserted_at) ->
        "Latest checkpoint snapshot recorded at #{inserted_at}."

      true ->
        "A checkpoint snapshot is available for debugger comparison."
    end
  end

  def human_gate_summary([]), do: nil

  def human_gate_summary(questions) do
    question = List.first(questions)

    %{
      owner: "Operator review required",
      action: question_prompt(question),
      detail:
        "Answer the open question on run detail or continue into the debugger inbox for timeline and checkpoint context.",
      provenance: question_provenance(question),
      effect:
        "Submitting an answer advances the waiting gate. It does not retry, replay, or resume the run by itself."
    }
  end

  def graph_markup(nil), do: nil
  def graph_markup(svg), do: HTML.raw(svg)

  def endpoint_catalog do
    [
      %{method: "GET", path: "/pipelines", label: "List runs"},
      %{method: "POST", path: "/pipelines", label: "Submit pipeline"},
      %{method: "POST", path: "/run", label: "Submit alias"},
      %{method: "GET", path: "/pipelines/:id", label: "Run status"},
      %{method: "GET", path: "/status?pipeline_id=:id", label: "Status alias"},
      %{method: "GET", path: "/pipelines/:id/context", label: "Context"},
      %{method: "GET", path: "/pipelines/:id/checkpoint", label: "Checkpoint"},
      %{method: "GET", path: "/pipelines/:id/events", label: "Events / SSE"},
      %{method: "GET", path: "/pipelines/:id/questions", label: "Pending questions"},
      %{method: "POST", path: "/pipelines/:id/questions/:qid/answer", label: "Answer question"},
      %{method: "POST", path: "/answer", label: "Answer alias"},
      %{method: "POST", path: "/pipelines/:id/cancel", label: "Cancel run"},
      %{
        method: "GET",
        path: "/pipelines/:id/graph?format=svg|json|dot|mermaid|text",
        label: "Graph formats"
      }
    ]
  end

  def build_answer_forms(questions) do
    questions
    |> Enum.map(fn question ->
      initial_params = %{
        "answer" => "",
        "choice" => default_single_choice(question),
        "choices" => [],
        "boolean" => "",
        "confirmation" => ""
      }

      {question["id"], Phoenix.Component.to_form(initial_params, as: :response)}
    end)
    |> Map.new()
  end

  def build_question_answer(nil, response), do: normalize_answer(response["answer"])

  def build_question_answer(question, response) do
    case question_input_mode(question) do
      mode when mode in ["boolean", "confirmation"] ->
        normalize_answer(response[mode])

      mode when mode in ["multi_select", "checkbox"] ->
        normalize_answers(response["choices"])

      "single_select" ->
        normalize_answer(response["choice"])

      "textarea" ->
        normalize_answer(response["answer"])

      _ ->
        cond do
          question_multiple?(question) -> normalize_answers(response["choices"])
          question_options(question) != [] -> normalize_answer(response["choice"])
          true -> normalize_answer(response["answer"])
        end
    end
  end

  def question_prompt(question) do
    question["prompt"] || question["question"] || question["text"] || "Question"
  end

  def question_options(question), do: question["options"] || []

  def question_type(question) do
    question["type"] || get_in(question, ["metadata", "question_type"]) || "QUESTION"
  end

  def question_input_mode(question) do
    question
    |> raw_question_input_mode()
    |> normalize_question_input_mode(question)
  end

  def question_multiple?(question), do: question["multiple"] == true

  def question_required?(question) do
    case question["required"] do
      false -> false
      _ -> true
    end
  end

  def question_timeout_label(question) do
    case question["timeout_seconds"] do
      value when is_integer(value) -> "#{value}s timeout"
      value when is_float(value) -> "#{trunc(value)}s timeout"
      _ -> nil
    end
  end

  def question_default_label(question) do
    case question["default"] do
      value when is_binary(value) and value != "" -> "default #{value}"
      _ -> nil
    end
  end

  def question_choice_options(question) do
    Enum.map(question_options(question), fn option ->
      {option["label"] || option["key"] || option["to"], option["key"] || option["to"]}
    end)
  end

  def response_field(form, field), do: form[field]

  def preview_json(value), do: Jason.encode_to_iodata!(value, pretty: true)

  def recent_events(events, limit \\ 10) do
    events
    |> Enum.reverse()
    |> Enum.take(limit)
  end

  def timeline_events(events) do
    Enum.sort_by(events, &event_sequence/1, :asc)
  end

  def default_debugger_filters do
    %{
      "type" => "all",
      "status" => "all",
      "node" => "all",
      "search" => "",
      "focus" => "all"
    }
  end

  def debugger_filters_from_params(params) do
    defaults = default_debugger_filters()

    %{
      "type" => blank_to_default(params["type"], defaults["type"]),
      "status" => blank_to_default(params["status"], defaults["status"]),
      "node" => blank_to_default(params["node"], defaults["node"]),
      "search" => String.trim(params["search"] || ""),
      "focus" => blank_to_default(params["focus"], defaults["focus"])
    }
  end

  def debugger_query_params(filters, selected_event_sequence \\ nil) do
    defaults = default_debugger_filters()

    filters
    |> Map.take(["type", "status", "node", "search", "focus"])
    |> Enum.reject(fn {key, value} ->
      value in [nil, "", defaults[key]]
    end)
    |> Enum.into(%{}, fn {key, value} -> {key, to_string(value)} end)
    |> maybe_put_selected_sequence(selected_event_sequence)
  end

  def filter_events(events, filters) do
    Enum.filter(events, fn event ->
      type_match?(event, filters["type"]) and
        status_match?(event, filters["status"]) and
        node_match?(event, filters["node"]) and
        focus_match?(event, filters["focus"]) and
        search_match?(event, filters["search"])
    end)
  end

  def event_filter_options(events) do
    %{
      types:
        events |> Enum.map(&event_type/1) |> Enum.reject(&blank?/1) |> Enum.uniq() |> Enum.sort(),
      statuses:
        events
        |> Enum.map(&event_status/1)
        |> Enum.reject(&blank?/1)
        |> Enum.uniq()
        |> Enum.sort(),
      nodes:
        events
        |> Enum.map(&event_node_id/1)
        |> Enum.reject(&blank?/1)
        |> Enum.uniq()
        |> Enum.sort()
    }
  end

  def find_event(events, nil), do: List.last(events)

  def find_event(events, sequence) when is_integer(sequence) do
    Enum.find(events, &(event_sequence(&1) == sequence)) || List.last(events)
  end

  def find_event(events, sequence) when is_binary(sequence) do
    case Integer.parse(sequence) do
      {value, ""} -> find_event(events, value)
      _ -> List.last(events)
    end
  end

  def event_sequence(event), do: Map.get(event, "sequence") || Map.get(event, :sequence) || 0

  def event_type(event) do
    Map.get(event, "type") || Map.get(event, :type) || get_in(event_payload(event), ["type"]) ||
      "event"
  end

  def event_status(event) do
    Map.get(event, "status") || Map.get(event, :status) ||
      get_in(event_payload(event), ["status"])
  end

  def event_timestamp(event) do
    Map.get(event, "timestamp") || Map.get(event, :timestamp) ||
      get_in(event_payload(event), ["timestamp"])
  end

  def event_payload(event) do
    Map.get(event, "payload") || Map.get(event, :payload) || event
  end

  def event_node_id(event) do
    payload = event_payload(event)

    payload["node_id"] ||
      payload["node"] ||
      payload["current_node"] ||
      payload["question_id"] ||
      payload["step"]
  end

  def event_title(event) do
    event
    |> event_type()
    |> Macro.underscore()
    |> String.replace("_", " ")
    |> String.replace(".", " ")
    |> String.trim()
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  def event_summary(event) do
    payload = event_payload(event)

    cond do
      present?(payload["message"]) ->
        display_value(payload["message"])

      present?(payload["detail"]) ->
        display_value(payload["detail"])

      present?(payload["question"]) ->
        display_value(payload["question"])

      present?(payload["prompt"]) ->
        display_value(payload["prompt"])

      present?(payload["error"]) ->
        "Error: #{display_value(payload["error"])}"

      present?(payload["current_node"]) ->
        "Current node #{payload["current_node"]}"

      present?(event_node_id(event)) and present?(event_status(event)) ->
        "#{event_node_id(event)} marked #{event_status(event)}"

      present?(event_node_id(event)) ->
        "Node #{event_node_id(event)} activity"

      true ->
        "Captured runtime event"
    end
  end

  def event_metadata(event) do
    payload = event_payload(event)

    [
      {"Type", event_type(event)},
      {"Status", event_status(event)},
      {"Node", event_node_id(event)},
      {"Sequence", event_sequence(event)},
      {"Timestamp", event_timestamp(event)},
      {"Question", payload["question_id"]},
      {"Transition", payload["to"]},
      {"Retry", payload["retry"]},
      {"Attempt", payload["attempt"]}
    ]
    |> Enum.reject(fn {_label, value} -> blank?(value) end)
  end

  def event_tone(event) do
    type = String.downcase(to_string(event_type(event)))
    status = String.downcase(to_string(event_status(event) || ""))

    cond do
      String.contains?(status, "fail") or String.contains?(type, "fail") or
          String.contains?(type, "error") ->
        "run-status-fail"

      String.contains?(status, "cancel") ->
        "run-status-cancelled"

      String.contains?(type, "question") or String.contains?(type, "human") ->
        "run-status-question"

      String.contains?(status, "success") or String.contains?(type, "complete") ->
        "run-status-success"

      true ->
        "run-status-running"
    end
  end

  def event_payload_without_wrapper(event) do
    event_payload(event)
    |> Map.drop(["payload"])
  end

  def context_checkpoint_diff(_context, nil),
    do: %{entries: [], counts: %{changed: 0, added: 0, removed: 0}}

  def context_checkpoint_diff(context, checkpoint) do
    checkpoint_context =
      checkpoint
      |> Map.get("context", %{})
      |> normalize_map()

    context = normalize_map(context)

    entries =
      diff_maps(checkpoint_context, context)
      |> Enum.sort_by(& &1.path)

    counts =
      Enum.reduce(entries, %{changed: 0, added: 0, removed: 0}, fn entry, acc ->
        Map.update!(acc, entry.kind, &(&1 + 1))
      end)

    %{entries: entries, counts: counts}
  end

  def question_inserted_at(question) do
    question["inserted_at"] || get_in(question, ["metadata", "inserted_at"])
  end

  def question_default_value(question) do
    question["default"] || get_in(question, ["metadata", "default"])
  end

  def question_default_badge(question) do
    case question_default_value(question) do
      value when is_binary(value) and value != "" ->
        "Default #{value}"

      value when is_list(value) and value != [] ->
        "Default #{Enum.map_join(value, ", ", &to_string/1)}"

      _ ->
        nil
    end
  end

  def question_provenance(question) do
    metadata = question["metadata"] || %{}

    [
      metadata["source"],
      metadata["handler"],
      metadata["node_type"],
      question_type(question)
    ]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" / ")
  end

  def question_option_notes(question) do
    question_options(question)
    |> Enum.map(fn option ->
      [option["key"], option["label"], option["to"]]
      |> Enum.reject(&blank?/1)
      |> Enum.join(" -> ")
    end)
  end

  def default_connection_label(:live), do: "Live"
  def default_connection_label(:reconnecting), do: "Reconnecting"
  def default_connection_label(:stale), do: "Polling fallback"
  def default_connection_label(_state), do: "Idle"

  def connection_detail(:live, :subscription), do: "Subscription updates are active."
  def connection_detail(:live, :polling), do: "The view is connected, but using polling."
  def connection_detail(:reconnecting, _mode), do: "Waiting for LiveView to reconnect."

  def connection_detail(:stale, :polling),
    do: "Subscriptions are unavailable, so polling is active."

  def connection_detail(:stale, _mode), do: "The view is stale and needs a refresh path."
  def connection_detail(_, _), do: "Connection state unknown."

  defp normalize_answer(answer) do
    trimmed = String.trim(to_string(answer || ""))
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_answers(values) do
    values
    |> List.wrap()
    |> Enum.map(&normalize_answer/1)
    |> Enum.reject(&is_nil/1)
  end

  defp default_single_choice(question) do
    case question_choice_options(question) do
      [] -> ""
      [{_label, value} | _] -> value || ""
    end
  end

  defp default_input_mode(question) do
    cond do
      question_multiple?(question) -> "multi_select"
      question_options(question) == [] -> "text"
      true -> "single_select"
    end
  end

  defp raw_question_input_mode(question) do
    get_in(question, ["metadata", "input_mode"]) || default_input_mode(question)
  end

  defp normalize_question_input_mode(mode, question) when mode in ["multi_select", "checkbox"] do
    if question_multiple?(question), do: mode, else: "single_select"
  end

  defp normalize_question_input_mode(mode, _question) when mode in ["select", "dropdown"],
    do: "single_select"

  defp normalize_question_input_mode(mode, _question), do: mode

  defp maybe_put_selected_sequence(params, nil), do: params
  defp maybe_put_selected_sequence(params, ""), do: params

  defp maybe_put_selected_sequence(params, sequence),
    do: Map.put(params, "event", to_string(sequence))

  defp type_match?(_event, "all"), do: true

  defp type_match?(event, type),
    do: String.downcase(to_string(event_type(event))) == String.downcase(type)

  defp status_match?(_event, "all"), do: true

  defp status_match?(event, status) do
    String.downcase(to_string(event_status(event) || "")) == String.downcase(status)
  end

  defp node_match?(_event, "all"), do: true
  defp node_match?(event, node), do: to_string(event_node_id(event) || "") == node

  defp focus_match?(_event, "all"), do: true

  defp focus_match?(event, "failures") do
    tone = event_tone(event)

    tone == "run-status-fail" or
      String.contains?(String.downcase(to_string(event_status(event) || "")), "fail")
  end

  defp focus_match?(event, "questions") do
    type = String.downcase(to_string(event_type(event)))
    String.contains?(type, "question") or String.contains?(type, "human")
  end

  defp focus_match?(event, "checkpoints") do
    payload = event_payload(event)

    String.contains?(String.downcase(to_string(event_type(event))), "checkpoint") or
      is_map(payload["checkpoint"]) or present?(payload["current_node"])
  end

  defp focus_match?(_event, _focus), do: true

  defp search_match?(_event, ""), do: true

  defp search_match?(event, search) do
    haystack =
      [
        event_type(event),
        event_status(event),
        event_node_id(event),
        event_summary(event),
        inspect(event_payload(event))
      ]
      |> Enum.reject(&blank?/1)
      |> Enum.join(" ")
      |> String.downcase()

    String.contains?(haystack, String.downcase(search))
  end

  defp diff_maps(left, right, path \\ [])

  defp diff_maps(left, right, path) when is_map(left) and is_map(right) do
    keys =
      (Map.keys(left) ++ Map.keys(right))
      |> Enum.uniq()
      |> Enum.sort()

    Enum.flat_map(keys, fn key ->
      left_value = Map.get(left, key, :__missing__)
      right_value = Map.get(right, key, :__missing__)

      cond do
        left_value == :__missing__ ->
          [diff_entry(:added, path ++ [key], nil, right_value)]

        right_value == :__missing__ ->
          [diff_entry(:removed, path ++ [key], left_value, nil)]

        is_map(left_value) and is_map(right_value) ->
          diff_maps(left_value, right_value, path ++ [key])

        left_value != right_value ->
          [diff_entry(:changed, path ++ [key], left_value, right_value)]

        true ->
          []
      end
    end)
  end

  defp diff_maps(left, right, path) when left != right do
    [diff_entry(:changed, path, left, right)]
  end

  defp diff_maps(_left, _right, _path), do: []

  defp diff_entry(kind, path, left, right) do
    %{
      kind: kind,
      path: Enum.map_join(path, ".", &to_string/1),
      left: left,
      right: right
    }
  end

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp display_value(value) when is_binary(value), do: value
  defp display_value(value) when is_atom(value), do: Atom.to_string(value)
  defp display_value(value) when is_number(value), do: to_string(value)

  defp display_value(value) do
    inspect(value, pretty: true, limit: 5)
  end

  defp blank_to_default(nil, default), do: default

  defp blank_to_default(value, default) do
    if blank?(value), do: default, else: to_string(value)
  end

  defp blank?(value), do: !present?(value)

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_list(value), do: value != []
  defp present?(value) when is_map(value), do: map_size(value) > 0
  defp present?(nil), do: false
  defp present?(false), do: false
  defp present?(value), do: value != ""
end
