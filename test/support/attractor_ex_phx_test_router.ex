defmodule AttractorExPhxTest.Router do
  use Plug.Router

  plug Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason
  plug :match
  plug :dispatch

  get "/pipelines" do
    notify({:get, conn.request_path, conn.query_string, %{}})
    json(conn, 200, %{"pipelines" => [%{"pipeline_id" => "pipeline-1", "status" => "success"}]})
  end

  post "/pipelines" do
    notify({:post, conn.request_path, "", conn.body_params})

    json(conn, 202, %{
      "pipeline_id" => Map.get(conn.body_params["opts"] || %{}, "pipeline_id", "generated-1")
    })
  end

  post "/run" do
    notify({:post, conn.request_path, "", conn.body_params})
    json(conn, 202, %{"pipeline_id" => "run-1"})
  end

  get "/error" do
    notify({:get, conn.request_path, conn.query_string, %{}})
    json(conn, 400, %{"error" => "boom"})
  end

  get "/pipelines/error" do
    notify({:get, conn.request_path, conn.query_string, %{}})
    json(conn, 400, %{"error" => "boom"})
  end

  get "/pipelines/:id" do
    notify({:get, conn.request_path, conn.query_string, %{}})
    json(conn, 200, %{"pipeline_id" => id, "status" => "running"})
  end

  get "/status" do
    notify({:get, conn.request_path, conn.query_string, %{}})
    json(conn, 200, %{"pipeline_id" => conn.params["pipeline_id"], "status" => "running"})
  end

  get "/pipelines/:id/context" do
    notify({:get, conn.request_path, conn.query_string, %{}})
    json(conn, 200, %{"context" => %{"pipeline_id" => id}})
  end

  get "/pipelines/:id/checkpoint" do
    notify({:get, conn.request_path, conn.query_string, %{}})
    json(conn, 200, %{"checkpoint" => %{"current_node" => "done", "pipeline_id" => id}})
  end

  get "/pipelines/:id/questions" do
    notify({:get, conn.request_path, conn.query_string, %{}})
    json(conn, 200, %{"questions" => [%{"id" => "gate", "pipeline_id" => id}]})
  end

  get "/pipelines/:id/events" do
    notify({:get, conn.request_path, conn.query_string, %{}})
    json(conn, 200, %{"events" => [%{"type" => "PipelineStarted", "pipeline_id" => id}]})
  end

  post "/pipelines/:id/cancel" do
    notify({:post, conn.request_path, "", conn.body_params})
    json(conn, 202, %{"pipeline_id" => id, "cancelled" => true})
  end

  post "/pipelines/:id/questions/:question_id/answer" do
    notify({:post, conn.request_path, "", conn.body_params})
    json(conn, 202, %{"pipeline_id" => id, "question_id" => question_id, "accepted" => true})
  end

  post "/answer" do
    notify({:post, conn.request_path, "", conn.body_params})

    json(conn, 202, %{
      "pipeline_id" => conn.body_params["pipeline_id"],
      "question_id" => conn.body_params["question_id"],
      "accepted" => true
    })
  end

  get "/pipelines/:id/graph" do
    notify({:get, conn.request_path, conn.query_string, %{}})

    case conn.params["format"] do
      "json" ->
        json(conn, 200, %{"graph" => %{"id" => id}})

      "dot" ->
        send_resp(conn, 200, "digraph #{id} {}")

      "mermaid" ->
        send_resp(conn, 200, "flowchart TD")

      "text" ->
        send_resp(conn, 200, "Graph: #{id}")

      nil ->
        send_resp(conn, 200, "<svg>#{id}</svg>")

      _other ->
        json(conn, 400, %{"error" => "unsupported"})
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, Jason.encode!(body))
  end

  defp notify(message) do
    if pid = Application.get_env(:attractor_phoenix, :attractor_ex_phx_test_listener) do
      send(pid, {:adapter_request, message})
    end
  end
end
