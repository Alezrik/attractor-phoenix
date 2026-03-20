defmodule AttractorPhoenixWeb.FailureReviewLive do
  use AttractorPhoenixWeb, :live_view

  alias AttractorExPhx.Client, as: AttractorAPI
  alias AttractorPhoenixWeb.OperatorRunData

  @impl true
  def mount(_params, _session, socket) do
    filters = default_filters()

    socket =
      socket
      |> stream_configure(:pipelines, dom_id: &"failure-pipeline-#{&1["pipeline_id"]}")
      |> assign(
        page_title: "Failure Review",
        filters: filters,
        filter_form: to_form(filters, as: :filters),
        total_failures: 0,
        total_questions: 0,
        last_updated_at: nil,
        error: nil
      )
      |> stream(:pipelines, [], reset: true)

    {:ok, load_failures(socket)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = filters_from_params(params)

    socket =
      socket
      |> assign(filters: filters, filter_form: to_form(filters, as: :filters))
      |> load_failures()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_failures", %{"filters" => params}, socket) do
    {:noreply, push_patch(socket, to: ~p"/failures?#{filter_query_params(params)}")}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/failures")}
  end

  def handle_event("resume_pipeline", %{"pipeline_id" => pipeline_id}, socket) do
    socket =
      case AttractorAPI.resume_pipeline(pipeline_id) do
        {:ok, _payload} -> load_failures(socket)
        {:error, message} -> assign(socket, error: message)
      end

    {:noreply, socket}
  end

  defp load_failures(socket) do
    case OperatorRunData.list_pipelines() do
      {:ok, %{"pipelines" => pipelines}} ->
        failures =
          pipelines
          |> filter_pipelines(socket.assigns.filters)
          |> Enum.map(&Map.put(&1, "failure_signal", OperatorRunData.failure_review_signal(&1)))

        socket
        |> assign(
          total_failures: length(failures),
          total_questions: Enum.reduce(failures, 0, &((&1["pending_questions"] || 0) + &2)),
          last_updated_at: DateTime.utc_now(),
          error: nil
        )
        |> stream(:pipelines, failures, reset: true)

      {:error, message} ->
        socket
        |> assign(error: message, total_failures: 0, total_questions: 0)
        |> stream(:pipelines, [], reset: true)
    end
  end

  defp default_filters do
    %{"status" => "all", "questions" => "all", "search" => ""}
  end

  defp filters_from_params(params) do
    %{
      "status" => blank_to_default(params["status"], "all"),
      "questions" => blank_to_default(params["questions"], "all"),
      "search" => String.trim(params["search"] || "")
    }
  end

  defp filter_query_params(params) do
    params
    |> Map.take(["status", "questions", "search"])
    |> Enum.reject(fn {_key, value} -> value in [nil, "", "all"] end)
    |> Map.new()
  end

  defp filter_pipelines(pipelines, filters) do
    pipelines
    |> Enum.filter(fn pipeline ->
      pipeline["status"] in ["fail", "cancelled"] and
        status_match?(pipeline, filters["status"]) and
        question_match?(pipeline, filters["questions"]) and
        search_match?(pipeline, filters["search"])
    end)
    |> Enum.sort_by(&{sort_priority(&1["status"]), &1["updated_at"] || ""}, :desc)
  end

  defp sort_priority("fail"), do: 2
  defp sort_priority("cancelled"), do: 1
  defp sort_priority(_status), do: 0

  defp status_match?(_pipeline, "all"), do: true
  defp status_match?(pipeline, status), do: to_string(pipeline["status"]) == status

  defp question_match?(_pipeline, "all"), do: true
  defp question_match?(pipeline, "open"), do: (pipeline["pending_questions"] || 0) > 0
  defp question_match?(pipeline, "clear"), do: (pipeline["pending_questions"] || 0) == 0
  defp question_match?(_pipeline, _filter), do: true

  defp search_match?(_pipeline, ""), do: true

  defp search_match?(pipeline, search) do
    pipeline["pipeline_id"]
    |> to_string()
    |> String.downcase()
    |> String.contains?(String.downcase(search))
  end

  defp blank_to_default(nil, default), do: default

  defp blank_to_default(value, default) do
    if String.trim(to_string(value)) == "", do: default, else: value
  end
end
