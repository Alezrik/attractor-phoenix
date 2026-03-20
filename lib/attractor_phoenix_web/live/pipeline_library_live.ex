defmodule AttractorPhoenixWeb.PipelineLibraryLive do
  use AttractorPhoenixWeb, :live_view

  alias AttractorPhoenix.PipelineLibrary

  @impl true
  def mount(_params, _session, socket) do
    entries = PipelineLibrary.list_entries()

    socket =
      socket
      |> assign(:page_title, "Pipeline Library")
      |> assign(:error, nil)
      |> assign(:editing_entry, nil)
      |> assign_library_entries(entries)
      |> assign(:form, build_form())

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      case {socket.assigns.live_action, params["id"]} do
        {:edit, id} ->
          case PipelineLibrary.get_entry(id) do
            {:ok, entry} ->
              assign(socket,
                editing_entry: entry,
                form: build_form(entry),
                error: nil,
                page_title: "Edit Library Pipeline"
              )

            {:error, :not_found} ->
              socket
              |> put_flash(:error, "Library pipeline not found.")
              |> push_navigate(to: ~p"/library")
          end

        {:new, _id} ->
          assign(socket,
            editing_entry: nil,
            form: build_form(),
            error: nil,
            page_title: "New Library Pipeline"
          )

        _ ->
          assign(socket,
            editing_entry: nil,
            form: build_form(),
            error: nil,
            page_title: "Pipeline Library"
          )
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("save", %{"library" => params}, socket) do
    case persist_entry(socket.assigns.live_action, socket.assigns.editing_entry, params) do
      {:ok, _entry, message} ->
        entries = PipelineLibrary.list_entries()

        {:noreply,
         socket
         |> assign_library_entries(entries)
         |> assign(:editing_entry, nil)
         |> assign(:form, build_form())
         |> assign(:error, nil)
         |> put_flash(:info, message)
         |> push_patch(to: ~p"/library")
         |> put_page_title("Pipeline Library")}

      {:error, message} ->
        {:noreply, assign(socket, error: message, form: build_form(params))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    socket =
      case PipelineLibrary.delete_entry(id) do
        :ok ->
          entries = PipelineLibrary.list_entries()

          socket
          |> assign_library_entries(entries)
          |> put_flash(:info, "Library pipeline deleted.")

        {:error, :not_found} ->
          put_flash(socket, :error, "Library pipeline not found.")
      end

    {:noreply, socket}
  end

  defp persist_entry(:edit, %{id: id}, params) do
    case PipelineLibrary.update_entry(id, params) do
      {:ok, entry} -> {:ok, entry, "Updated library artifact #{entry.name} (#{entry.id})."}
      {:error, %{message: message}} -> {:error, message}
      {:error, :not_found} -> {:error, "Library pipeline not found."}
    end
  end

  defp persist_entry(_action, _entry, params) do
    case PipelineLibrary.create_entry(params) do
      {:ok, entry} ->
        {:ok, entry,
         "Saved new library artifact #{entry.name} (#{entry.id}). Future edits update this same artifact."}

      {:error, %{message: message}} ->
        {:error, message}
    end
  end

  defp build_form(entry \\ %{}) do
    to_form(
      %{
        "name" => Map.get(entry, :name, Map.get(entry, "name", "")),
        "description" => Map.get(entry, :description, Map.get(entry, "description", "")),
        "dot" => Map.get(entry, :dot, Map.get(entry, "dot", "")),
        "context_json" => Map.get(entry, :context_json, Map.get(entry, "context_json", "{}"))
      },
      as: :library
    )
  end

  defp put_page_title(socket, title) do
    assign(socket, :page_title, title)
  end

  defp assign_library_entries(socket, entries) do
    recent_entries = Enum.take(entries, 3)

    socket
    |> assign(:entries, entries)
    |> assign(:recent_entries, recent_entries)
    |> assign(:featured_entry, List.first(entries))
    |> assign(:entry_count, length(entries))
  end
end
