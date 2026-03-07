defmodule AttractorEx.HTTP.Router do
  @moduledoc false

  use Plug.Router

  alias AttractorEx.Parser
  alias AttractorEx.HTTP.Manager

  @graph_formats MapSet.new(["dot", "json", "mermaid", "svg", "text"])
  @default_max_body_length 1_000_000

  plug Plug.Logger
  plug :match

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason,
    length: @default_max_body_length

  plug :dispatch

  def init(opts), do: opts

  def call(conn, opts) do
    conn
    |> Plug.Conn.put_private(:attractor_http_opts, opts)
    |> super(opts)
  rescue
    Plug.Parsers.RequestTooLargeError ->
      json(conn, 413, %{
        "error" => "request body too large",
        "max_bytes" => @default_max_body_length
      })

    Plug.Parsers.ParseError ->
      json(conn, 400, %{"error" => "invalid json body"})
  end

  post "/pipelines" do
    manager = manager!(conn)
    payload = conn.body_params
    dot = first_present_dot(payload["dot"], payload["dot_source"])
    context = payload["context"] || %{}
    opts = decode_pipeline_opts(payload["opts"] || %{})

    case present_string(dot) do
      {:ok, value} ->
        case Manager.create_pipeline(manager, value, context, opts) do
          {:ok, id} -> json(conn, 202, %{"pipeline_id" => id})
          {:error, reason} -> json(conn, 400, %{"error" => inspect(reason)})
        end

      _ ->
        json(conn, 400, %{"error" => "pipeline dot source is required"})
    end
  end

  get "/pipelines" do
    manager = manager!(conn)

    case Manager.list_pipelines(manager) do
      {:ok, pipelines} -> json(conn, 200, %{"pipelines" => pipelines})
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
          "pending_questions" => map_size(pipeline.questions),
          "logs_root" => pipeline.logs_root,
          "inserted_at" => pipeline.inserted_at,
          "updated_at" => pipeline.updated_at,
          "has_checkpoint" => is_map(pipeline.checkpoint)
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
      if events_stream?(conn) do
        conn =
          conn
          |> put_common_headers()
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
        json(conn, 200, %{"events" => events})
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
      "pipeline_id" => :pipeline_id,
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

  defp first_present_dot(primary, fallback) do
    case present_string(primary) do
      {:ok, value} -> value
      :error -> fallback
    end
  end

  defp present_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: :error, else: {:ok, value}
  end

  defp present_string(_value), do: :error

  defp json(conn, status, payload) do
    body = Jason.encode!(payload)

    conn
    |> put_common_headers()
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, body)
  end

  defp encode_sse(event) do
    "event: #{Map.get(event, "type", "message")}\ndata: #{Jason.encode!(event)}\n\n"
  end

  defp events_stream?(conn), do: conn.params["stream"] not in ["false", "0"]

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
        |> put_common_headers()
        |> Plug.Conn.put_resp_content_type("text/vnd.graphviz")
        |> Plug.Conn.put_resp_header("content-disposition", "inline; filename=\"pipeline.dot\"")
        |> Plug.Conn.send_resp(200, dot)

      "json" ->
        case Parser.parse(dot) do
          {:ok, graph} -> json(conn, 200, graph_to_json(graph))
          {:error, reason} -> json(conn, 422, %{"error" => reason})
        end

      "mermaid" ->
        case Parser.parse(dot) do
          {:ok, graph} ->
            conn
            |> put_common_headers()
            |> Plug.Conn.put_resp_content_type("text/plain")
            |> Plug.Conn.put_resp_header(
              "content-disposition",
              "inline; filename=\"pipeline.mmd\""
            )
            |> Plug.Conn.send_resp(200, graph_to_mermaid(graph))

          {:error, reason} ->
            json(conn, 422, %{"error" => reason})
        end

      "text" ->
        case Parser.parse(dot) do
          {:ok, graph} ->
            conn
            |> put_common_headers()
            |> Plug.Conn.put_resp_content_type("text/plain")
            |> Plug.Conn.put_resp_header(
              "content-disposition",
              "inline; filename=\"pipeline.txt\""
            )
            |> Plug.Conn.send_resp(200, graph_to_text(graph))

          {:error, reason} ->
            json(conn, 422, %{"error" => reason})
        end

      "svg" ->
        conn
        |> put_common_headers()
        |> Plug.Conn.put_resp_content_type("image/svg+xml")
        |> Plug.Conn.send_resp(200, dot_to_svg(dot))

      {:error, format} ->
        json(conn, 400, %{
          "error" => "unsupported graph format",
          "format" => format,
          "supported_formats" => @graph_formats |> Enum.sort()
        })
    end
  end

  defp graph_format(conn) do
    conn.params["format"]
    |> case do
      nil -> "svg"
      value when is_binary(value) -> normalize_graph_format(value)
      _ -> "svg"
    end
  end

  defp normalize_graph_format(value) do
    format = String.downcase(String.trim(value))

    if MapSet.member?(@graph_formats, format) do
      format
    else
      {:error, format}
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

  defp graph_to_mermaid(graph) do
    lines =
      [
        "flowchart TD"
        | Enum.map(Enum.sort_by(graph.nodes, fn {id, _node} -> id end), fn {id, node} ->
            "  #{mermaid_id(id)}[\"#{escape_mermaid_text(node_label(node))}\"]"
          end)
      ] ++
        Enum.map(graph.edges, fn edge ->
          "  #{mermaid_id(edge.from)} -->|#{escape_mermaid_text(edge_label(edge))}| #{mermaid_id(edge.to)}"
        end)

    Enum.join(lines, "\n")
  end

  defp graph_to_text(graph) do
    node_lines =
      graph.nodes
      |> Enum.sort_by(fn {id, _node} -> id end)
      |> Enum.map(fn {id, node} ->
        "  - #{id} [type=#{node.type}, shape=#{node.shape}]#{text_prompt_suffix(node)}"
      end)

    edge_lines =
      Enum.map(graph.edges, fn edge ->
        "  - #{edge.from} -> #{edge.to}#{text_edge_suffix(edge)}"
      end)

    [
      "Graph: #{graph.id}",
      "Goal: #{Map.get(graph.attrs, "goal", "-")}",
      "Nodes:",
      Enum.join(node_lines, "\n"),
      "Edges:",
      Enum.join(edge_lines, "\n")
    ]
    |> Enum.join("\n")
  end

  defp node_label(node) do
    [node.id, node.type]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" :: ")
  end

  defp edge_label(edge) do
    cond do
      is_binary(edge.condition) and edge.condition != "" ->
        edge.condition

      is_binary(edge.status) and edge.status != "" ->
        edge.status

      is_binary(edge.attrs["label"]) and String.trim(edge.attrs["label"]) != "" ->
        edge.attrs["label"]

      true ->
        ""
    end
  end

  defp text_prompt_suffix(node) do
    case String.trim(node.prompt || "") do
      "" -> ""
      prompt -> ", prompt=#{inspect(prompt)}"
    end
  end

  defp text_edge_suffix(edge) do
    case String.trim(edge_label(edge)) do
      "" -> ""
      label -> " [label=#{inspect(label)}]"
    end
  end

  defp mermaid_id(id) do
    id
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
  end

  defp escape_mermaid_text(text) do
    text
    |> to_string()
    |> String.replace("\"", "\\\"")
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

  defp put_common_headers(conn) do
    conn
    |> Plug.Conn.put_resp_header("cache-control", "no-store")
    |> Plug.Conn.put_resp_header("x-content-type-options", "nosniff")
  end
end
