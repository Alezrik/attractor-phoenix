defmodule AttractorPhoenixWeb.DashboardLive do
  use AttractorPhoenixWeb, :live_view

  alias AttractorExPhx
  alias AttractorPhoenixWeb.OperatorRunData

  @refresh_interval_ms 3_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> stream_configure(:pipelines, dom_id: &"pipeline-#{&1["pipeline_id"]}")
      |> assign(
        page_title: "Operator Dashboard",
        pipelines: [],
        filters: default_filters(),
        filter_form: to_form(default_filters(), as: :filters),
        filtered_total: 0,
        total_pipelines: 0,
        running_pipelines: 0,
        successful_pipelines: 0,
        failed_pipelines: 0,
        cancelled_pipelines: 0,
        total_questions: 0,
        connection_state: if(connected?(socket), do: :live, else: :idle),
        update_mode: :subscription,
        error: nil,
        subscribed_pipeline_ids: MapSet.new(),
        last_updated_at: nil
      )
      |> stream(:pipelines, [], reset: true)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = filters_from_params(params)

    socket =
      socket
      |> assign(filters: filters, filter_form: to_form(filters, as: :filters))
      |> refresh_dashboard()

    {:noreply, socket}
  end

  @impl true
  def handle_event("filter_runs", %{"filters" => params}, socket) do
    {:noreply, push_patch(socket, to: ~p"/?#{filter_query_params(params)}")}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/")}
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
        {:attractor_ex_event, _event},
        %{assigns: %{update_mode: :subscription}} = socket
      ) do
    {:noreply, refresh_dashboard(socket)}
  end

  def handle_info({:attractor_ex_event, _event}, socket), do: {:noreply, socket}

  def handle_info(:poll_dashboard, %{assigns: %{update_mode: :polling}} = socket) do
    socket =
      socket
      |> refresh_dashboard()
      |> schedule_poll()

    {:noreply, socket}
  end

  def handle_info(:poll_dashboard, socket), do: {:noreply, socket}

  defp refresh_dashboard(socket) do
    case OperatorRunData.list_pipelines() do
      {:ok, %{"pipelines" => pipelines}} ->
        filtered = filter_pipelines(pipelines, socket.assigns.filters)
        stats = OperatorRunData.summarize_pipelines(pipelines)

        socket
        |> assign(stats)
        |> assign(
          pipelines: pipelines,
          filtered_total: length(filtered),
          error: nil,
          last_updated_at: DateTime.utc_now()
        )
        |> stream(:pipelines, filtered, reset: true)
        |> sync_pipeline_subscriptions(pipelines)

      {:error, message} ->
        assign(socket, error: message)
    end
  end

  defp sync_pipeline_subscriptions(socket, pipelines) do
    if connected?(socket) and socket.assigns.update_mode == :subscription do
      pipeline_ids = MapSet.new(Enum.map(pipelines, & &1["pipeline_id"]))
      current = socket.assigns.subscribed_pipeline_ids

      added_ids = MapSet.difference(pipeline_ids, current)

      case subscribe_pipeline_ids(added_ids) do
        :ok ->
          removed_ids = MapSet.difference(current, pipeline_ids)
          unsubscribe_pipeline_ids(removed_ids)

          assign(socket,
            subscribed_pipeline_ids: pipeline_ids,
            connection_state: :live
          )

        {:error, _reason} ->
          socket
          |> assign(
            update_mode: :polling,
            connection_state: :stale
          )
          |> schedule_poll()
      end
    else
      socket
    end
  end

  defp subscribe_pipeline_ids(pipeline_ids) do
    Enum.reduce_while(pipeline_ids, :ok, fn pipeline_id, :ok ->
      case AttractorExPhx.subscribe_pipeline(pipeline_id) do
        {:ok, _snapshot} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp unsubscribe_pipeline_ids(pipeline_ids) do
    Enum.each(pipeline_ids, &AttractorExPhx.unsubscribe_pipeline/1)
  end

  defp maybe_restore_live_updates(%{assigns: %{update_mode: :subscription}} = socket), do: socket

  defp maybe_restore_live_updates(socket) do
    socket
    |> assign(update_mode: :subscription, error: nil)
    |> refresh_dashboard()
  end

  defp schedule_poll(socket) do
    Process.send_after(self(), :poll_dashboard, @refresh_interval_ms)
    socket
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
    Enum.filter(pipelines, fn pipeline ->
      status_match?(pipeline, filters["status"]) and
        question_match?(pipeline, filters["questions"]) and
        search_match?(pipeline, filters["search"])
    end)
  end

  defp status_match?(_pipeline, "all"), do: true

  defp status_match?(pipeline, status) do
    to_string(pipeline["status"]) == status
  end

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

  defp live_connection_state(:subscription), do: :live
  defp live_connection_state(:polling), do: :stale
end
