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
end
