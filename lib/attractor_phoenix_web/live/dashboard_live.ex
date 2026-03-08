defmodule AttractorPhoenixWeb.DashboardLive do
  use AttractorPhoenixWeb, :live_view

  alias AttractorExPhx.Client, as: AttractorAPI
  alias Phoenix.HTML

  @refresh_interval_ms 3_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        page_title: "Dashboard",
        pipelines: [],
        selected_pipeline_id: nil,
        selected_pipeline: nil,
        selected_status_alias: nil,
        selected_context: %{},
        selected_checkpoint: nil,
        selected_questions: [],
        answer_forms: %{},
        selected_events: [],
        selected_graphs: %{},
        error: nil
      )

    socket =
      case refresh_dashboard(socket, nil) do
        {:ok, refreshed} -> refreshed
        {:error, refreshed} -> refreshed
      end

    if connected?(socket) do
      Process.send_after(self(), :refresh_dashboard, @refresh_interval_ms)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    selected_pipeline_id = params["pipeline"]

    case refresh_dashboard(socket, selected_pipeline_id) do
      {:ok, socket} -> {:noreply, socket}
      {:error, socket} -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:refresh_dashboard, socket) do
    socket =
      case refresh_dashboard(socket, socket.assigns.selected_pipeline_id) do
        {:ok, refreshed} -> refreshed
        {:error, refreshed} -> refreshed
      end

    Process.send_after(self(), :refresh_dashboard, @refresh_interval_ms)
    {:noreply, socket}
  end

  defp refresh_dashboard(socket, selected_pipeline_id) do
    with {:ok, %{"pipelines" => pipelines}} <- AttractorAPI.list_pipelines() do
      selected_pipeline_id = resolve_selected_pipeline_id(pipelines, selected_pipeline_id)

      socket =
        socket
        |> assign(
          pipelines: pipelines,
          selected_pipeline_id: selected_pipeline_id,
          error: nil
        )
        |> assign_overview_stats(pipelines)

      if selected_pipeline_id do
        refresh_selected_pipeline(socket, selected_pipeline_id)
      else
        {:ok,
         assign(socket,
           selected_pipeline: nil,
           selected_status_alias: nil,
           selected_context: %{},
           selected_checkpoint: nil,
           selected_questions: [],
           answer_forms: %{},
           selected_events: [],
           selected_graphs: %{}
         )}
      end
    else
      {:error, message} ->
        {:error, assign(socket, error: message)}
    end
  end

  @impl true
  def handle_event("cancel_pipeline", _params, %{assigns: %{selected_pipeline_id: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_event("cancel_pipeline", _params, socket) do
    socket =
      case AttractorAPI.cancel_pipeline(socket.assigns.selected_pipeline_id) do
        {:ok, _payload} ->
          refresh_now(socket)

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
    answer =
      response
      |> Map.get("answer", "")
      |> normalize_answer()

    socket =
      case AttractorAPI.answer_question(socket.assigns.selected_pipeline_id, question_id, answer) do
        {:ok, _payload} ->
          refresh_now(socket)

        {:error, message} ->
          assign(socket, error: message)
      end

    {:noreply, socket}
  end

  defp refresh_selected_pipeline(socket, pipeline_id) do
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

      {:ok,
       assign(socket,
         selected_pipeline: summary,
         selected_status_alias: status_alias,
         selected_context: context_payload["context"] || %{},
         selected_checkpoint: checkpoint_payload["checkpoint"],
         selected_questions: questions,
         answer_forms: build_answer_forms(questions),
         selected_events: events_payload["events"] || [],
         selected_graphs: %{
           "svg" => graph_svg,
           "json" => graph_json["graph"] || %{},
           "dot" => graph_dot,
           "mermaid" => graph_mermaid,
           "text" => graph_text
         }
       )}
    else
      {:error, message} ->
        {:error, assign(socket, error: message)}
    end
  end

  defp resolve_selected_pipeline_id(pipelines, selected_pipeline_id) do
    pipeline_ids = MapSet.new(Enum.map(pipelines, & &1["pipeline_id"]))

    cond do
      is_binary(selected_pipeline_id) and MapSet.member?(pipeline_ids, selected_pipeline_id) ->
        selected_pipeline_id

      match?([%{} | _], pipelines) ->
        hd(pipelines)["pipeline_id"]

      true ->
        nil
    end
  end

  defp assign_overview_stats(socket, pipelines) do
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

    assign(socket,
      total_pipelines: length(pipelines),
      running_pipelines: counts.running,
      successful_pipelines: counts.success,
      failed_pipelines: counts.fail,
      cancelled_pipelines: counts.cancelled,
      total_questions: counts.questions
    )
  end

  defp normalize_status(status) when status in [:success, "success"], do: :success
  defp normalize_status(status) when status in [:fail, "fail"], do: :fail
  defp normalize_status(status) when status in [:cancelled, "cancelled"], do: :cancelled
  defp normalize_status(_status), do: :running

  defp graph_markup(nil), do: nil
  defp graph_markup(svg), do: HTML.raw(svg)

  defp endpoint_catalog do
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

  defp bar_width(whole, count) when whole > 0,
    do: "width: #{Float.round(count / whole * 100, 1)}%"

  defp bar_width(_whole, _count), do: "width: 0%"

  defp build_answer_forms(questions) do
    questions
    |> Enum.map(fn question ->
      {question["id"], to_form(%{"answer" => ""}, as: :response)}
    end)
    |> Map.new()
  end

  defp normalize_answer(answer) do
    trimmed = String.trim(to_string(answer || ""))
    if trimmed == "", do: nil, else: trimmed
  end

  defp refresh_now(socket) do
    case refresh_dashboard(socket, socket.assigns.selected_pipeline_id) do
      {:ok, refreshed} -> refreshed
      {:error, refreshed} -> refreshed
    end
  end

  defp question_prompt(question) do
    question["prompt"] || question["question"] || "Question"
  end

  defp question_options(question) do
    question["options"] || []
  end

  defp preview_json(value) do
    Jason.encode_to_iodata!(value, pretty: true)
  end
end
