defmodule AttractorPhoenixWeb.PipelineBuilderLive do
  use AttractorPhoenixWeb, :live_view

  alias AttractorPhoenix.AttractorAPI

  @refresh_interval_ms 1_500

  @impl true
  def mount(_params, _session, socket) do
    socket =
      assign(socket,
        page_title: "Pipeline Builder",
        dot: sample_dot(),
        context_json: "{}",
        form: build_form(sample_dot(), "{}"),
        result: nil,
        error: nil,
        current_pipeline_id: nil,
        events: [],
        checkpoint: nil,
        questions: [],
        status: nil
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("run_pipeline", %{"pipeline" => params}, socket) do
    dot = Map.get(params, "dot", socket.assigns.dot)
    context_json = Map.get(params, "context_json", socket.assigns.context_json)

    with {:ok, context} <- decode_context(context_json),
         {:ok, %{"pipeline_id" => pipeline_id}} <-
           AttractorAPI.create_pipeline(dot, context, logs_root: "tmp/runs"),
         {:ok, socket} <-
           refresh_pipeline(
             assign(socket,
               dot: dot,
               context_json: context_json,
               form: build_form(dot, context_json),
               current_pipeline_id: pipeline_id
             ),
             pipeline_id
           ) do
      {:noreply, schedule_refresh(socket)}
    else
      {:error, message} ->
        {:noreply,
         assign(socket,
           dot: dot,
           context_json: context_json,
           form: build_form(dot, context_json),
           current_pipeline_id: nil,
           result: nil,
           status: nil,
           events: [],
           checkpoint: nil,
           questions: [],
           error: to_string(message)
         )}
    end
  end

  @impl true
  def handle_info(:refresh_pipeline, %{assigns: %{current_pipeline_id: nil}} = socket) do
    {:noreply, socket}
  end

  def handle_info(:refresh_pipeline, %{assigns: %{current_pipeline_id: pipeline_id}} = socket) do
    case refresh_pipeline(socket, pipeline_id) do
      {:ok, socket} -> {:noreply, maybe_schedule_refresh(socket)}
      {:error, socket} -> {:noreply, socket}
    end
  end

  defp decode_context(context_json) when is_binary(context_json) do
    case Jason.decode(context_json) do
      {:ok, context} when is_map(context) -> {:ok, context}
      {:ok, _} -> {:error, "Context JSON must be an object."}
      {:error, error} -> {:error, "Context JSON is invalid: #{Exception.message(error)}"}
    end
  end

  defp sample_dot do
    """
    digraph attractor {
      graph [goal="Hello World", label="hello-world"]
      start [shape=Mdiamond, label="start"]
      hello [shape=parallelogram, label="hello", tool_command="echo hello world"]
      done [shape=Msquare, label="done"]
      goodbye [shape=parallelogram, label="goodbye", tool_command="echo the end of the world is near"]

      start -> hello
      hello -> done [status="success"]
      hello -> goodbye [status="fail"]
      goodbye -> done
    }
    """
  end

  defp refresh_pipeline(socket, pipeline_id) do
    with {:ok, summary} <- AttractorAPI.get_pipeline(pipeline_id),
         {:ok, context_payload} <- AttractorAPI.get_pipeline_context(pipeline_id),
         {:ok, checkpoint_payload} <- AttractorAPI.get_pipeline_checkpoint(pipeline_id),
         {:ok, questions_payload} <- AttractorAPI.get_pipeline_questions(pipeline_id),
         {:ok, events_payload} <- AttractorAPI.get_pipeline_events(pipeline_id) do
      result = %{
        status: summary["status"],
        run_id: pipeline_id,
        logs_root: summary["logs_root"],
        context: context_payload["context"] || %{},
        checkpoint: checkpoint_payload["checkpoint"],
        pending_questions: questions_payload["questions"] || [],
        events: events_payload["events"] || [],
        event_count: summary["event_count"]
      }

      {:ok,
       assign(socket,
         form: build_form(socket.assigns.dot, socket.assigns.context_json),
         result: result,
         status: summary["status"],
         checkpoint: checkpoint_payload["checkpoint"],
         questions: questions_payload["questions"] || [],
         events: events_payload["events"] || [],
         error: nil
       )}
    else
      {:error, message} ->
        {:error, assign(socket, error: message)}
    end
  end

  defp maybe_schedule_refresh(%{assigns: %{status: status}} = socket)
       when status in [:success, :fail, :cancelled, "success", "fail", "cancelled"],
       do: socket

  defp maybe_schedule_refresh(socket), do: schedule_refresh(socket)

  defp schedule_refresh(socket) do
    Process.send_after(self(), :refresh_pipeline, @refresh_interval_ms)
    socket
  end

  defp build_form(dot, context_json) do
    to_form(
      %{
        "dot" => dot,
        "context_json" => context_json
      },
      as: :pipeline
    )
  end
end
