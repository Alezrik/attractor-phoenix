defmodule AttractorEx.HTTP.GraphRenderer do
  @moduledoc """
  Renders parsed graphs into presentation-friendly HTTP formats.

  Supported outputs include SVG, JSON, Mermaid, and plain text summaries.
  """

  alias AttractorEx.Graph

  @canvas_padding 48
  @column_gap 260
  @row_gap 132
  @node_width 184
  @node_height 76

  @doc "Renders a graph as an SVG card-style diagram."
  def to_svg(%Graph{} = graph) do
    positions = layout(graph)
    layers = positions |> Map.values() |> Enum.map(& &1.layer)
    rows = positions |> Map.values() |> Enum.map(& &1.row)
    max_layer = if layers == [], do: 0, else: Enum.max(layers)
    max_row = if rows == [], do: 0, else: Enum.max(rows)
    width = @canvas_padding * 2 + @node_width + max_layer * @column_gap
    height = 160 + @canvas_padding * 2 + @node_height + max_row * @row_gap

    edge_markup =
      graph.edges
      |> Enum.map_join("\n", &edge_svg(&1, positions))

    node_markup =
      graph.nodes
      |> Enum.sort_by(fn {id, _node} -> id end)
      |> Enum.map_join("\n", fn {_id, node} -> node_svg(node, positions[node.id]) end)

    goal = blank_to_nil(graph.attrs["goal"])
    subtitle = if goal, do: "Goal: #{goal}", else: "Executable pipeline graph"

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}" role="img" aria-labelledby="graph-title graph-subtitle">
      <defs>
        <linearGradient id="pipeline-bg" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stop-color="#f8f4eb" />
          <stop offset="100%" stop-color="#efe5d4" />
        </linearGradient>
        <filter id="card-shadow" x="-10%" y="-10%" width="120%" height="120%">
          <feDropShadow dx="0" dy="8" stdDeviation="10" flood-color="#42210b" flood-opacity="0.12" />
        </filter>
        <marker id="arrowhead" markerWidth="12" markerHeight="12" refX="10" refY="6" orient="auto" markerUnits="strokeWidth">
          <path d="M 0 0 L 12 6 L 0 12 z" fill="#8c6a43" />
        </marker>
      </defs>
      <rect width="100%" height="100%" fill="url(#pipeline-bg)" rx="28" />
      <text id="graph-title" x="#{@canvas_padding}" y="56" font-family="ui-sans-serif, system-ui, sans-serif" font-size="28" font-weight="700" fill="#2d1f12">Attractor Pipeline</text>
      <text id="graph-subtitle" x="#{@canvas_padding}" y="86" font-family="ui-sans-serif, system-ui, sans-serif" font-size="14" fill="#6f5438">#{escape(subtitle)}</text>
      <g class="edges">
        #{edge_markup}
      </g>
      <g class="nodes">
        #{node_markup}
      </g>
    </svg>
    """
  end

  @doc "Renders a graph as structured JSON."
  def to_json(%Graph{} = graph) do
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

  @doc "Renders a graph as Mermaid flowchart text."
  def to_mermaid(%Graph{} = graph) do
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

  @doc "Renders a graph as a plain-text summary."
  def to_text(%Graph{} = graph) do
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

  defp layout(%Graph{} = graph) do
    node_ids = graph.nodes |> Map.keys() |> Enum.sort()
    incoming = incoming_map(graph)
    roots = Enum.filter(node_ids, &(Map.get(incoming, &1, 0) == 0))
    ordered_roots = if roots == [], do: node_ids, else: roots

    layers =
      ordered_roots
      |> Enum.reduce({%{}, ordered_roots}, fn root, {acc, queue} ->
        if Map.has_key?(acc, root) do
          {acc, queue}
        else
          walk_layers(graph, root, acc, queue)
        end
      end)
      |> elem(0)
      |> ensure_all_nodes(node_ids)

    rows_by_layer =
      layers
      |> Enum.group_by(fn {_id, layer} -> layer end, fn {id, _layer} -> id end)
      |> Enum.map(fn {layer, ids} -> {layer, Enum.sort(ids)} end)
      |> Map.new()

    Enum.reduce(rows_by_layer, %{}, fn {layer, ids}, acc ->
      Enum.with_index(ids)
      |> Enum.reduce(acc, fn {id, row}, positions ->
        x = @canvas_padding + layer * @column_gap
        y = 120 + @canvas_padding + row * @row_gap
        Map.put(positions, id, %{x: x, y: y, layer: layer, row: row})
      end)
    end)
  end

  defp walk_layers(graph, root, layers, queue) do
    do_walk_layers(graph, [{root, 0}], layers, MapSet.new(queue))
  end

  defp do_walk_layers(_graph, [], layers, _seen), do: {layers, []}

  defp do_walk_layers(graph, [{node_id, layer} | rest], layers, seen) do
    current_layer = max(layer, Map.get(layers, node_id, 0))
    layers = Map.put(layers, node_id, current_layer)

    {next_items, seen} =
      graph.edges
      |> Enum.filter(&(&1.from == node_id))
      |> Enum.sort_by(& &1.to)
      |> Enum.reduce({[], seen}, fn edge, {items, current_seen} ->
        next_layer =
          if Map.get(layers, edge.to, -1) > current_layer do
            Map.get(layers, edge.to)
          else
            current_layer + 1
          end

        if MapSet.member?(current_seen, {edge.to, next_layer}) do
          {items, current_seen}
        else
          {[{edge.to, next_layer} | items], MapSet.put(current_seen, {edge.to, next_layer})}
        end
      end)

    do_walk_layers(graph, rest ++ Enum.reverse(next_items), layers, seen)
  end

  defp ensure_all_nodes(layers, node_ids) do
    Enum.reduce(node_ids, layers, fn id, acc ->
      Map.put_new(acc, id, disconnected_layer(acc))
    end)
  end

  defp disconnected_layer(layers) when map_size(layers) == 0, do: 0

  defp disconnected_layer(layers) do
    layers
    |> Map.values()
    |> Enum.max()
    |> Kernel.+(1)
  end

  defp incoming_map(%Graph{} = graph) do
    Enum.reduce(graph.edges, %{}, fn edge, acc -> Map.update(acc, edge.to, 1, &(&1 + 1)) end)
  end

  defp edge_svg(edge, positions) do
    from = positions[edge.from]
    to = positions[edge.to]
    from_x = from.x + @node_width
    from_y = from.y + div(@node_height, 2)
    to_x = to.x
    to_y = to.y + div(@node_height, 2)
    delta_x = max(80, abs(to_x - from_x) |> div(2))
    control_a = from_x + delta_x
    control_b = to_x - delta_x
    label = blank_to_nil(edge_label(edge))
    label_x = div(from_x + to_x, 2)
    label_y = div(from_y + to_y, 2) - 10

    label_markup =
      if label do
        ~s(<text x="#{label_x}" y="#{label_y}" text-anchor="middle" font-family="ui-sans-serif, system-ui, sans-serif" font-size="12" font-weight="600" fill="#7a4f18">#{escape(label)}</text>)
      else
        ""
      end

    """
    <g class="edge">
      <path d="M #{from_x} #{from_y} C #{control_a} #{from_y}, #{control_b} #{to_y}, #{to_x} #{to_y}" fill="none" stroke="#8c6a43" stroke-width="2.5" marker-end="url(#arrowhead)" />
      #{label_markup}
    </g>
    """
  end

  defp node_svg(node, %{x: x, y: y}) do
    title = primary_node_title(node)
    subtitle = node.type
    prompt = node_prompt(node)
    accent = node_accent(node)

    """
    <g class="node node-#{escape_attr(css_name(node.type))}" transform="translate(#{x}, #{y})" filter="url(#card-shadow)">
      #{node_shape(node, accent)}
      <text x="22" y="30" font-family="ui-sans-serif, system-ui, sans-serif" font-size="17" font-weight="700" fill="#2d1f12">#{escape(title)}</text>
      <text x="22" y="50" font-family="ui-monospace, monospace" font-size="11" font-weight="600" letter-spacing="0.08em" fill="#6f5438">#{escape(String.upcase(subtitle))}</text>
      #{prompt_svg(prompt)}
    </g>
    """
  end

  defp node_shape(node, accent) do
    fill = shape_fill(node)
    stroke = accent

    case node.shape do
      "diamond" ->
        ~s(<polygon points="92,0 184,38 92,76 0,38" fill="#{fill}" stroke="#{stroke}" stroke-width="2.5" />)

      "hexagon" ->
        ~s(<polygon points="26,0 158,0 184,38 158,76 26,76 0,38" fill="#{fill}" stroke="#{stroke}" stroke-width="2.5" />)

      "parallelogram" ->
        ~s(<polygon points="18,0 184,0 166,76 0,76" fill="#{fill}" stroke="#{stroke}" stroke-width="2.5" />)

      "house" ->
        ~s(<polygon points="22,24 92,0 162,24 162,76 22,76" fill="#{fill}" stroke="#{stroke}" stroke-width="2.5" />)

      "Mdiamond" ->
        ~s(<polygon points="92,0 184,38 92,76 0,38" fill="#{fill}" stroke="#{stroke}" stroke-width="2.5" />)

      "Msquare" ->
        ~s(<rect x="0" y="0" width="184" height="76" rx="14" fill="#{fill}" stroke="#{stroke}" stroke-width="2.5" />)

      _ ->
        ~s(<rect x="0" y="0" width="184" height="76" rx="24" fill="#{fill}" stroke="#{stroke}" stroke-width="2.5" />)
    end
  end

  defp prompt_svg(nil), do: ""
  defp prompt_svg(""), do: ""

  defp prompt_svg(prompt) do
    ~s(<text x="22" y="68" font-family="ui-sans-serif, system-ui, sans-serif" font-size="11" fill="#5e4b34">#{escape(prompt)}</text>)
  end

  defp primary_node_title(node) do
    blank_to_nil(node.attrs["label"]) || node.id
  end

  defp node_prompt(node) do
    node.prompt
    |> blank_to_nil()
    |> maybe_truncate(36)
  end

  defp node_accent(node) do
    cond do
      node.type == "start" -> "#3b7f4a"
      node.type == "exit" -> "#2f6f9f"
      node.type == "wait.human" -> "#c46b1f"
      node.goal_gate -> "#9a3d5d"
      true -> "#5f4a33"
    end
  end

  defp shape_fill(node) do
    cond do
      node.type == "start" -> "#e6f5ea"
      node.type == "exit" -> "#e7f0f9"
      node.type == "wait.human" -> "#fff1df"
      node.goal_gate -> "#f9e5ec"
      true -> "#fffaf2"
    end
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

  defp css_name(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp maybe_truncate(nil, _max), do: nil

  defp maybe_truncate(value, max) when byte_size(value) <= max, do: value

  defp maybe_truncate(value, max) do
    value
    |> binary_part(0, max - 1)
    |> Kernel.<>("...")
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) do
    trimmed = value |> to_string() |> String.trim()
    if trimmed == "", do: nil, else: trimmed
  end

  defp escape(value) do
    value
    |> to_string()
    |> Plug.HTML.html_escape()
    |> IO.iodata_to_binary()
  end

  defp escape_attr(value), do: escape(value)
end
