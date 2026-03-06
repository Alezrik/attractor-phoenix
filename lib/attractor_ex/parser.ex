defmodule AttractorEx.Parser do
  @moduledoc false

  alias AttractorEx.{Edge, Graph, Node}

  @id_pattern ~r/^[A-Za-z_][A-Za-z0-9_]*$/
  @graph_attr_decl_pattern ~r/^([A-Za-z_][A-Za-z0-9_\.]*)\s*=\s*(.+)$/

  def parse(dot) when is_binary(dot) do
    cleaned = strip_comments(dot)

    with {:ok, graph_name, body} <- parse_root(cleaned) do
      graph = %Graph{id: graph_name}

      parsed =
        body
        |> split_statements()
        |> Enum.reduce_while(graph, fn statement, acc ->
          case parse_statement(statement, acc) do
            {:ok, next_graph} -> {:cont, next_graph}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      case parsed do
        {:error, reason} -> {:error, reason}
        graph_value -> {:ok, finalize_graph(graph_value)}
      end
    end
  end

  defp parse_root(dot) do
    case Regex.run(~r/digraph\s+("?[\w\-]+"?)?\s*\{(?<body>.*)\}\s*$/ms, dot, capture: :all_names) do
      [body] ->
        name =
          case Regex.run(~r/digraph\s+("?[\w\-]+"?)?\s*\{/m, dot, capture: :all_but_first) do
            [value] ->
              candidate =
                value |> String.trim() |> String.trim_leading("\"") |> String.trim_trailing("\"")

              if candidate != "" and valid_identifier?(candidate), do: candidate, else: "pipeline"

            _ ->
              "pipeline"
          end

        {:ok, name, body}

      _ ->
        {:error, "Invalid DOT input. Expected `digraph ... { ... }`."}
    end
  end

  defp split_statements(body) do
    body
    |> String.replace("\r", "")
    |> String.split(~r/;\s*|\n/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 in ["", "{", "}"] or String.starts_with?(&1, "subgraph ")))
  end

  defp parse_statement("graph " <> rest, graph),
    do: parse_default_block(rest, fn attrs -> %{graph | attrs: Map.merge(graph.attrs, attrs)} end)

  defp parse_statement("node " <> rest, graph),
    do:
      parse_default_block(rest, fn attrs ->
        %{graph | node_defaults: Map.merge(graph.node_defaults, attrs)}
      end)

  defp parse_statement("edge " <> rest, graph),
    do:
      parse_default_block(rest, fn attrs ->
        %{graph | edge_defaults: Map.merge(graph.edge_defaults, attrs)}
      end)

  defp parse_statement(statement, graph) do
    cond do
      String.contains?(statement, "--") ->
        {:error, "Undirected edges are not supported. Use `->`."}

      String.contains?(statement, "->") ->
        parse_edge_statement(statement, graph)

      Regex.match?(@graph_attr_decl_pattern, statement) ->
        parse_graph_attr_decl(statement, graph)

      true ->
        parse_node_statement(statement, graph)
    end
  end

  defp parse_graph_attr_decl(statement, graph) do
    case Regex.run(@graph_attr_decl_pattern, statement, capture: :all_but_first) do
      [key, value] ->
        {:ok, %{graph | attrs: Map.put(graph.attrs, key, parse_value(value))}}

      _ ->
        {:error, "Invalid graph attribute declaration: #{statement}"}
    end
  end

  defp parse_default_block(statement_tail, updater) do
    attrs =
      statement_tail
      |> String.trim()
      |> parse_attribute_block()

    {:ok, updater.(attrs)}
  end

  defp parse_node_statement(statement, graph) do
    {id_part, attrs_part} = split_attrs(statement)
    id = normalize_id(id_part)

    if id == "" or not valid_identifier?(id) do
      {:error, "Invalid node declaration: #{statement}"}
    else
      attrs = parse_attribute_block(attrs_part)

      existing =
        case Map.get(graph.nodes, id) do
          nil -> %Node{id: id, attrs: %{}}
          node -> node
        end

      merged = %{existing | attrs: Map.merge(existing.attrs, attrs)}
      {:ok, %{graph | nodes: Map.put(graph.nodes, id, merged)}}
    end
  end

  defp parse_edge_statement(statement, graph) do
    {path_part, attrs_part} = split_attrs(statement)

    ids =
      path_part
      |> String.split("->")
      |> Enum.map(&normalize_id/1)
      |> Enum.reject(&(&1 == ""))

    if length(ids) < 2 or Enum.any?(ids, &(not valid_identifier?(&1))) do
      {:error, "Invalid edge declaration: #{statement}"}
    else
      attrs = Map.merge(graph.edge_defaults, parse_attribute_block(attrs_part))

      next_graph =
        ids
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.reduce(graph, fn [from, to], acc ->
          with_from = ensure_node(acc, from)
          with_nodes = ensure_node(with_from, to)
          edge = Edge.new(from, to, attrs)
          %{with_nodes | edges: with_nodes.edges ++ [edge]}
        end)

      {:ok, next_graph}
    end
  end

  defp ensure_node(graph, id) do
    case Map.get(graph.nodes, id) do
      nil -> %{graph | nodes: Map.put(graph.nodes, id, %Node{id: id, attrs: %{}})}
      _node -> graph
    end
  end

  defp finalize_graph(graph) do
    finalized_nodes =
      graph.nodes
      |> Enum.map(fn {id, node} ->
        attrs = Map.merge(graph.node_defaults, node.attrs)
        {id, Node.new(id, attrs)}
      end)
      |> Map.new()

    %{graph | nodes: finalized_nodes}
  end

  defp split_attrs(statement) do
    case String.split(statement, "[", parts: 2) do
      [id_part, attrs] -> {String.trim(id_part), "[" <> attrs}
      [id_part] -> {String.trim(id_part), "[]"}
    end
  end

  defp parse_attribute_block("[" <> rest) do
    rest
    |> String.trim_trailing("]")
    |> split_attr_pairs()
    |> Enum.map(&String.trim/1)
    |> Enum.reduce(%{}, fn pair, acc ->
      case String.split(pair, "=", parts: 2) do
        [key, value] ->
          Map.put(acc, String.trim(key), parse_value(value))

        _ ->
          acc
      end
    end)
  end

  defp parse_attribute_block(_), do: %{}

  defp split_attr_pairs(text) do
    {parts, current, _in_quotes} =
      text
      |> String.graphemes()
      |> Enum.reduce({[], "", false}, fn char, {parts, current, in_quotes} ->
        cond do
          char == "\"" ->
            {parts, current <> char, not in_quotes}

          char == "," and not in_quotes ->
            {[current | parts], "", in_quotes}

          true ->
            {parts, current <> char, in_quotes}
        end
      end)

    [current | parts]
    |> Enum.reverse()
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  defp parse_value(value) do
    normalized =
      value
      |> String.trim()
      |> String.trim_leading("\"")
      |> String.trim_trailing("\"")
      |> String.replace("\\\"", "\"")
      |> String.replace("\\\\", "\\")

    cond do
      normalized == "true" ->
        true

      normalized == "false" ->
        false

      Regex.match?(~r/^-?\d+$/, normalized) ->
        String.to_integer(normalized)

      Regex.match?(~r/^-?\d*\.\d+$/, normalized) ->
        String.to_float(normalized)

      true ->
        normalized
    end
  end

  defp normalize_id(id) do
    trimmed = String.trim(id)

    case Regex.run(@id_pattern, trimmed) do
      [plain] when is_binary(plain) and plain != "" -> plain
      _ -> ""
    end
  end

  defp valid_identifier?(id), do: Regex.match?(@id_pattern, id)

  defp strip_comments(dot) do
    dot
    |> String.replace(~r/\/\*[\s\S]*?\*\//, "")
    |> String.replace(~r/\/\/[^\n]*/, "")
  end
end
