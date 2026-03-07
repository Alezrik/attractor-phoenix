defmodule AttractorPhoenixWeb.DashboardLive do
  use AttractorPhoenixWeb, :live_view

  alias AttractorPhoenix.AttractorAPI
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
        selected_context: %{},
        selected_checkpoint: nil,
        selected_questions: [],
        selected_events: [],
        graph_svg: nil,
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
           selected_context: %{},
           selected_checkpoint: nil,
           selected_questions: [],
           selected_events: [],
           graph_svg: nil
         )}
      end
    else
      {:error, message} ->
        {:error, assign(socket, error: message)}
    end
  end

  defp refresh_selected_pipeline(socket, pipeline_id) do
    with {:ok, summary} <- AttractorAPI.get_pipeline(pipeline_id),
         {:ok, context_payload} <- AttractorAPI.get_pipeline_context(pipeline_id),
         {:ok, checkpoint_payload} <- AttractorAPI.get_pipeline_checkpoint(pipeline_id),
         {:ok, questions_payload} <- AttractorAPI.get_pipeline_questions(pipeline_id),
         {:ok, events_payload} <- AttractorAPI.get_pipeline_events(pipeline_id),
         {:ok, graph_svg} <- AttractorAPI.get_pipeline_graph_svg(pipeline_id) do
      {:ok,
       assign(socket,
         selected_pipeline: summary,
         selected_context: context_payload["context"] || %{},
         selected_checkpoint: checkpoint_payload["checkpoint"],
         selected_questions: questions_payload["questions"] || [],
         selected_events: events_payload["events"] || [],
         graph_svg: graph_svg
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

  defp bar_width(whole, count) when whole > 0,
    do: "width: #{Float.round(count / whole * 100, 1)}%"

  defp bar_width(_whole, _count), do: "width: 0%"

  defp preview_json(value) do
    Jason.encode_to_iodata!(value, pretty: true)
  end
end
