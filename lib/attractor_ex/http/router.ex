defmodule AttractorEx.HTTP.Router do
  @moduledoc false

  use Plug.Router

  alias AttractorEx.Parser
  alias AttractorEx.HTTP.Manager

  plug Plug.Logger
  plug :match
  plug Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason
  plug :dispatch

  def init(opts), do: opts

  def call(conn, opts) do
    conn
    |> Plug.Conn.put_private(:attractor_http_opts, opts)
    |> super(opts)
  end

  post "/pipelines" do
    manager = manager!(conn)
    payload = conn.body_params
    dot = payload["dot"] || payload["dot_source"] || ""
    context = payload["context"] || %{}
    opts = decode_pipeline_opts(payload["opts"] || %{})

    case Manager.create_pipeline(manager, dot, context, opts) do
      {:ok, id} -> json(conn, 202, %{"pipeline_id" => id})
      {:error, reason} -> json(conn, 400, %{"error" => inspect(reason)})
    end
  end

  get "/pipelines/:id" do
    manager = manager!(conn)

    case Manager.get_pipeline(manager, id) do
      {:ok, pipeline} ->
        json(conn, 200, %{
          "pipeline_id" => pipeline.id,
          "status" => pipeline.status,
          "event_count" => length(pipeline.events),
          "pending_questions" => map_size(pipeline.questions)
        })

      {:error, :not_found} ->
        json(conn, 404, %{"error" => "pipeline not found"})
    end
  end

  get "/pipelines/:id/events" do
    manager = manager!(conn)
    registry = registry!(conn)

    with {:ok, events} <- Manager.pipeline_events(manager, id),
         {:ok, pipeline} <- Manager.get_pipeline(manager, id) do
      conn =
        conn
        |> Plug.Conn.put_resp_content_type("text/event-stream")
        |> Plug.Conn.send_chunked(200)

      conn =
        Enum.reduce_while(events, conn, fn event, acc ->
          case Plug.Conn.chunk(acc, encode_sse(event)) do
            {:ok, next_conn} -> {:cont, next_conn}
            {:error, _reason} -> {:halt, acc}
          end
        end)

      if terminal?(pipeline.status) do
        conn
      else
        {:ok, _} = Registry.register(registry, {:pipeline_events, id}, true)
        :ok = Manager.subscribe(manager, id, self())
        sse_loop(conn, pipeline.status)
      end
    else
      {:error, :not_found} -> json(conn, 404, %{"error" => "pipeline not found"})
    end
  end

  post "/pipelines/:id/cancel" do
    manager = manager!(conn)

    case Manager.cancel(manager, id) do
      :ok -> json(conn, 202, %{"pipeline_id" => id, "status" => "cancelled"})
      {:error, :not_found} -> json(conn, 404, %{"error" => "pipeline not found"})
    end
  end

  get "/pipelines/:id/graph" do
    manager = manager!(conn)

    case Manager.pipeline_graph(manager, id) do
      {:ok, dot} ->
        send_graph(conn, dot)

      {:error, :not_found} ->
        json(conn, 404, %{"error" => "pipeline not found"})
    end
  end

  get "/pipelines/:id/questions" do
    manager = manager!(conn)

    case Manager.pending_questions(manager, id) do
      {:ok, questions} ->
        json(
          conn,
          200,
          %{"questions" => Enum.map(questions, &Map.drop(&1, [:waiter, :ref]))}
        )

      {:error, :not_found} ->
        json(conn, 404, %{"error" => "pipeline not found"})
    end
  end

  post "/pipelines/:id/questions/:qid/answer" do
    manager = manager!(conn)
    answer = conn.body_params["answer"] || conn.body_params["value"]

    case Manager.submit_answer(manager, id, qid, answer) do
      :ok -> json(conn, 202, %{"pipeline_id" => id, "question_id" => qid, "accepted" => true})
      {:error, :not_found} -> json(conn, 404, %{"error" => "question not found"})
    end
  end

  get "/pipelines/:id/checkpoint" do
    manager = manager!(conn)

    case Manager.pipeline_checkpoint(manager, id) do
      {:ok, checkpoint} -> json(conn, 200, %{"checkpoint" => checkpoint})
      {:error, :not_found} -> json(conn, 404, %{"error" => "pipeline not found"})
    end
  end

  get "/pipelines/:id/context" do
    manager = manager!(conn)

    case Manager.pipeline_context(manager, id) do
      {:ok, context} -> json(conn, 200, %{"context" => context})
      {:error, :not_found} -> json(conn, 404, %{"error" => "pipeline not found"})
    end
  end

  match _ do
    json(conn, 404, %{"error" => "not found"})
  end

  defp manager!(conn) do
    get_in(conn.private, [:attractor_http_opts, :manager]) || AttractorEx.HTTP.Manager
  end

  defp registry!(conn) do
    get_in(conn.private, [:attractor_http_opts, :registry]) || AttractorEx.HTTP.Registry
  end

  defp decode_pipeline_opts(opts) when is_map(opts) do
    allowed_keys = %{
      "max_steps" => :max_steps,
      "logs_root" => :logs_root,
      "retry_sleep" => :retry_sleep,
      "initial_delay_ms" => :initial_delay_ms,
      "backoff_factor" => :backoff_factor,
      "max_delay_ms" => :max_delay_ms,
      "retry_jitter" => :retry_jitter
    }

    opts
    |> Enum.reduce([], fn {key, value}, acc ->
      case Map.get(allowed_keys, to_string(key)) do
        nil -> acc
        atom_key -> [{atom_key, value} | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp decode_pipeline_opts(_opts), do: []

  defp json(conn, status, payload) do
    body = Jason.encode!(payload)

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, body)
  end

  defp encode_sse(event) do
    "event: #{Map.get(event, "type", "message")}\ndata: #{Jason.encode!(event)}\n\n"
  end

  defp sse_loop(conn, status) when status in [:success, :fail, :cancelled], do: conn

  defp sse_loop(conn, _status) do
    receive do
      {:pipeline_event, event} ->
        case Plug.Conn.chunk(conn, encode_sse(event)) do
          {:ok, next_conn} ->
            if terminal?(Map.get(event, "status")) or
                 Map.get(event, "type") in ["PipelineCompleted", "PipelineFailed"] do
              next_conn
            else
              sse_loop(next_conn, Map.get(event, "status"))
            end

          {:error, _reason} ->
            conn
        end
    after
      15_000 ->
        case Plug.Conn.chunk(conn, ": keep-alive\n\n") do
          {:ok, next_conn} -> sse_loop(next_conn, nil)
          {:error, _reason} -> conn
        end
    end
  end

  defp terminal?(status),
    do: status in [:success, :fail, :cancelled, "success", "fail", "cancelled"]

  defp send_graph(conn, dot) do
    case graph_format(conn) do
      "dot" ->
        conn
        |> Plug.Conn.put_resp_content_type("text/vnd.graphviz")
        |> Plug.Conn.send_resp(200, dot)

      "json" ->
        case Parser.parse(dot) do
          {:ok, graph} -> json(conn, 200, graph_to_json(graph))
          {:error, reason} -> json(conn, 422, %{"error" => reason})
        end

      _ ->
        conn
        |> Plug.Conn.put_resp_content_type("image/svg+xml")
        |> Plug.Conn.send_resp(200, dot_to_svg(dot))
    end
  end

  defp graph_format(conn) do
    conn.params["format"]
    |> case do
      value when is_binary(value) -> String.downcase(String.trim(value))
      _ -> "svg"
    end
  end

  defp graph_to_json(graph) do
    %{
      "graph" => %{
        "id" => graph.id,
        "attrs" => graph.attrs,
        "node_defaults" => graph.node_defaults,
        "edge_defaults" => graph.edge_defaults,
        "nodes" =>
          graph.nodes
          |> Enum.map(fn {id, node} ->
            {id,
             %{
               "id" => node.id,
               "type" => node.type,
               "shape" => node.shape,
               "prompt" => node.prompt,
               "goal_gate" => node.goal_gate,
               "retry_target" => node.retry_target,
               "fallback_retry_target" => node.fallback_retry_target,
               "attrs" => node.attrs
             }}
          end)
          |> Map.new(),
        "edges" =>
          Enum.map(graph.edges, fn edge ->
            %{
              "from" => edge.from,
              "to" => edge.to,
              "condition" => edge.condition,
              "status" => edge.status,
              "attrs" => edge.attrs
            }
          end)
      }
    }
  end

  defp dot_to_svg(dot) do
    escaped =
      dot
      |> Plug.HTML.html_escape()
      |> IO.iodata_to_binary()

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="960" height="540" viewBox="0 0 960 540">
      <rect width="100%" height="100%" fill="#f5f2ea" />
      <text x="40" y="56" font-family="monospace" font-size="20" fill="#3a3126">Attractor Pipeline</text>
      <foreignObject x="32" y="80" width="896" height="420">
        <pre xmlns="http://www.w3.org/1999/xhtml" style="margin:0;font:14px/1.45 monospace;color:#2f2a24;white-space:pre-wrap;">#{escaped}</pre>
      </foreignObject>
    </svg>
    """
  end
end
