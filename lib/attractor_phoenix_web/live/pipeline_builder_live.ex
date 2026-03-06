defmodule AttractorPhoenixWeb.PipelineBuilderLive do
  use AttractorPhoenixWeb, :live_view

  alias AttractorEx

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "attractor-phoenix",
       dot: sample_dot(),
       context_json: "{}",
       result: nil,
       error: nil
     )}
  end

  @impl true
  def handle_event("run_pipeline", %{"pipeline" => params}, socket) do
    dot = Map.get(params, "dot", socket.assigns.dot)
    context_json = Map.get(params, "context_json", socket.assigns.context_json)

    with {:ok, context} <- decode_context(context_json),
         {:ok, result} <- AttractorEx.run(dot, context, logs_root: "tmp/runs") do
      {:noreply, assign(socket, dot: dot, context_json: context_json, result: result, error: nil)}
    else
      {:error, %{diagnostics: diagnostics}} ->
        {:noreply,
         assign(socket,
           dot: dot,
           context_json: context_json,
           result: nil,
           error: "Validation failed: #{Jason.encode_to_iodata!(diagnostics)}"
         )}

      {:error, %{error: message}} ->
        {:noreply,
         assign(socket, dot: dot, context_json: context_json, result: nil, error: message)}

      {:error, message} ->
        {:noreply,
         assign(socket,
           dot: dot,
           context_json: context_json,
           result: nil,
           error: to_string(message)
         )}
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
end
