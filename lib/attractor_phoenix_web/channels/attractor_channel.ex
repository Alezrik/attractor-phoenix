defmodule AttractorPhoenixWeb.AttractorChannel do
  @moduledoc """
  Phoenix Channel that streams `AttractorEx` pipeline snapshots and live updates.
  """

  use AttractorPhoenixWeb, :channel

  alias AttractorExPhx

  @impl true
  def join("attractor:pipeline:" <> pipeline_id, _payload, socket) do
    case AttractorExPhx.subscribe_pipeline(pipeline_id) do
      {:ok, snapshot} ->
        send(self(), {:push_snapshot, snapshot})
        {:ok, assign(socket, :pipeline_id, pipeline_id)}

      {:error, :not_found} ->
        {:error, %{reason: "pipeline_not_found"}}

      {:error, reason} ->
        {:error, %{reason: inspect(reason)}}
    end
  end

  @impl true
  def handle_in("answer_question", %{"question_id" => question_id} = params, socket) do
    answer = Map.get(params, "answer") || Map.get(params, "value")

    case AttractorExPhx.answer_question(socket.assigns.pipeline_id, question_id, answer) do
      {:ok, payload} -> {:reply, {:ok, payload}, socket}
      {:error, reason} -> {:reply, {:error, %{error: reason}}, socket}
    end
  end

  def handle_in("cancel_pipeline", _params, socket) do
    case AttractorExPhx.cancel_pipeline(socket.assigns.pipeline_id) do
      {:ok, payload} -> {:reply, {:ok, payload}, socket}
      {:error, reason} -> {:reply, {:error, %{error: reason}}, socket}
    end
  end

  @impl true
  def handle_info({:push_snapshot, snapshot}, socket) do
    push(socket, "snapshot", snapshot)
    {:noreply, socket}
  end

  def handle_info({:attractor_ex_event, event}, socket) do
    push(socket, "pipeline_event", event)
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    AttractorExPhx.unsubscribe_pipeline(socket.assigns.pipeline_id)
    :ok
  end
end
