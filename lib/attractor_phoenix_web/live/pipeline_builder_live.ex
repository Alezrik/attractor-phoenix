defmodule AttractorPhoenixWeb.PipelineBuilderLive do
  use AttractorPhoenixWeb, :live_view

  alias AttractorExPhx.Client, as: AttractorAPI
  alias AttractorPhoenix.DotGenerator
  alias AttractorPhoenix.LLMSetup
  alias AttractorPhoenix.PipelineLibrary

  @refresh_interval_ms 1_500

  @impl true
  def mount(_params, _session, socket) do
    dot = sample_dot()
    context_json = "{}"

    socket =
      assign(socket,
        page_title: "Pipeline Builder",
        dot: dot,
        context_json: context_json,
        form: build_form(dot, context_json),
        result: nil,
        error: nil,
        current_pipeline_id: nil,
        submit_endpoint: "run",
        events: [],
        checkpoint: nil,
        questions: [],
        status: nil,
        graph_json: nil,
        loaded_library_entry: nil
      )
      |> assign_create_state()

    {:ok, socket}
  end

  def handle_params(_params, _uri, %{assigns: %{live_action: :create}} = socket) do
    {:noreply, assign_create_state(socket)}
  end

  @impl true
  def handle_params(%{"library" => id}, _uri, socket) do
    socket =
      case PipelineLibrary.get_entry(id) do
        {:ok, entry} ->
          assign(socket,
            page_title: "Pipeline Builder",
            dot: entry.dot,
            context_json: entry.context_json,
            form: build_form(entry.dot, entry.context_json, entry),
            loaded_library_entry: entry,
            error: nil
          )
          |> assign_create_state()

        {:error, :not_found} ->
          socket
          |> put_flash(:error, "Library pipeline not found.")
          |> assign(loaded_library_entry: nil)
      end

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("change_create", %{"create" => params}, socket) do
    {:noreply,
     assign_create_state(
       socket,
       Map.get(params, "prompt", ""),
       Map.get(params, "provider", ""),
       Map.get(params, "model", "")
     )}
  end

  @impl true
  def handle_event("generate_dot", %{"create" => params}, socket) do
    prompt = Map.get(params, "prompt", "")
    provider = Map.get(params, "provider", "")
    model = Map.get(params, "model", "")

    case DotGenerator.generate(prompt, provider: provider, model: model) do
      {:ok, dot} ->
        {:noreply,
         socket
         |> assign(
           dot: dot,
           form:
             build_form(dot, socket.assigns.context_json, socket.assigns.loaded_library_entry),
           error: nil
         )
         |> assign_create_state()
         |> put_flash(:info, "Generated DOT loaded into the builder.")
         |> push_patch(to: ~p"/builder")}

      {:error, message} ->
        {:noreply, assign_create_state(socket, prompt, provider, model, message)}
    end
  end

  @impl true
  def handle_event(
        "pipeline_action",
        %{"pipeline" => %{"action" => "save_library"} = params},
        socket
      ) do
    dot = Map.get(params, "dot", socket.assigns.dot)
    context_json = Map.get(params, "context_json", socket.assigns.context_json)

    attrs = %{
      "name" => Map.get(params, "library_name", ""),
      "description" => Map.get(params, "library_description", ""),
      "dot" => dot,
      "context_json" => context_json
    }

    result =
      case socket.assigns.loaded_library_entry do
        %{id: id} -> PipelineLibrary.update_entry(id, attrs)
        nil -> PipelineLibrary.create_entry(attrs)
      end

    case result do
      {:ok, entry} ->
        {:noreply,
         socket
         |> assign(
           dot: dot,
           context_json: context_json,
           form: build_form(dot, context_json, entry),
           loaded_library_entry: entry,
           error: nil
         )
         |> put_flash(:info, "Pipeline saved to the library.")
         |> push_patch(to: ~p"/builder?library=#{entry.id}")}

      {:error, %{message: message}} ->
        {:noreply,
         assign(socket,
           dot: dot,
           context_json: context_json,
           form: build_form(dot, context_json, params),
           error: message
         )}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Library pipeline not found.")}
    end
  end

  def handle_event("pipeline_action", %{"pipeline" => params}, socket) do
    dot = Map.get(params, "dot", socket.assigns.dot)
    context_json = Map.get(params, "context_json", socket.assigns.context_json)

    transport =
      case Map.get(params, "action", "run") do
        "pipelines" -> "pipelines"
        _ -> "run"
      end

    with {:ok, context} <- decode_context(context_json),
         {:ok, %{"pipeline_id" => pipeline_id}} <- submit_pipeline(dot, context, transport),
         {:ok, socket} <-
           refresh_pipeline(
             assign(socket,
               dot: dot,
               context_json: context_json,
               form: build_form(dot, context_json, socket.assigns.loaded_library_entry || params),
               current_pipeline_id: pipeline_id,
               submit_endpoint: transport
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
           form: build_form(dot, context_json, socket.assigns.loaded_library_entry || params),
           current_pipeline_id: nil,
           submit_endpoint: transport,
           result: nil,
           status: nil,
           events: [],
           checkpoint: nil,
           questions: [],
           graph_json: nil,
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
         {:ok, events_payload} <- AttractorAPI.get_pipeline_events(pipeline_id),
         {:ok, graph_payload} <- AttractorAPI.get_pipeline_graph_json(pipeline_id) do
      result = %{
        status: summary["status"],
        run_id: pipeline_id,
        logs_root: summary["logs_root"],
        submit_endpoint: socket.assigns.submit_endpoint,
        context: context_payload["context"] || %{},
        checkpoint: checkpoint_payload["checkpoint"],
        pending_questions: questions_payload["questions"] || [],
        events: events_payload["events"] || [],
        event_count: summary["event_count"],
        graph: graph_payload["graph"] || %{}
      }

      {:ok,
       assign(socket,
         form:
           build_form(
             socket.assigns.dot,
             socket.assigns.context_json,
             socket.assigns.loaded_library_entry
           ),
         result: result,
         status: summary["status"],
         checkpoint: checkpoint_payload["checkpoint"],
         questions: questions_payload["questions"] || [],
         events: events_payload["events"] || [],
         graph_json: graph_payload["graph"] || %{},
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
    build_form(dot, context_json, nil)
  end

  defp assign_create_state(socket, prompt \\ "", provider \\ nil, model \\ nil, error \\ nil) do
    create_form = build_create_form(prompt, provider, model)
    selected_provider = create_form[:provider].value |> blank_to_nil()

    assign(socket,
      create_form: create_form,
      create_provider_options: provider_options(),
      create_model_options: model_options(selected_provider),
      create_error: error
    )
  end

  defp build_create_form(prompt, provider, model) do
    defaults = LLMSetup.default_selection()
    provider = blank_to_nil(provider) || defaults.provider || ""

    model =
      blank_to_nil(model) ||
        if provider != "" do
          provider_default_model(provider, defaults.model)
        else
          defaults.model || ""
        end

    to_form(
      %{"prompt" => prompt, "provider" => provider, "model" => model || ""},
      as: :create
    )
  end

  defp provider_options do
    LLMSetup.available_models()
    |> Enum.map(& &1.provider)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&{String.capitalize(&1), &1})
  end

  defp model_options(nil) do
    case LLMSetup.default_selection().provider do
      nil ->
        model_options("")

      provider ->
        model_options(provider)
    end
  end

  defp model_options(provider) when is_binary(provider) do
    LLMSetup.available_models()
    |> Enum.filter(fn model ->
      provider == "" or model.provider == provider
    end)
    |> Enum.map(fn model ->
      {"#{String.capitalize(model.provider)} / #{model.id}", model.id}
    end)
  end

  defp build_form(dot, context_json, library_entry) do
    library_entry = library_form_attrs(library_entry)

    to_form(
      %{
        "dot" => dot,
        "context_json" => context_json,
        "library_name" => library_entry.name,
        "library_description" => library_entry.description
      },
      as: :pipeline
    )
  end

  defp library_form_attrs(%{name: name, description: description}) do
    %{name: name, description: description}
  end

  defp library_form_attrs(%{"library_name" => name, "library_description" => description}) do
    %{name: name || "", description: description || ""}
  end

  defp library_form_attrs(_entry) do
    %{name: "", description: ""}
  end

  defp provider_default_model(provider, default_model) do
    provider_models =
      LLMSetup.available_models()
      |> Enum.filter(&(&1.provider == provider))

    cond do
      default_model && Enum.any?(provider_models, &(&1.id == default_model)) ->
        default_model

      provider_models != [] ->
        hd(provider_models).id

      true ->
        ""
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    trimmed = value |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end

  defp submit_pipeline(dot, context, "pipelines") do
    AttractorAPI.create_pipeline(dot, context, logs_root: "tmp/runs")
  end

  defp submit_pipeline(dot, context, _transport) do
    AttractorAPI.run_pipeline(dot, context, logs_root: "tmp/runs")
  end
end
