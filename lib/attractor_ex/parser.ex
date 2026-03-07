defmodule AttractorEx.Parser do
  @moduledoc false

  alias AttractorEx.{Edge, Graph, ModelStylesheet, Node}

  @bare_id_pattern ~r/^[A-Za-z_][A-Za-z0-9_]*$/
  @numeric_id_pattern ~r/^-?(?:\d+|\d*\.\d+)$/
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
        graph_value -> finalize_graph(graph_value)
      end
    end
  end

  defp parse_root(dot) do
    case Regex.run(~r/^\s*digraph(?:\s+(?<graph_id>.+?))?\s*\{(?<body>.*)\}\s*$/ms, dot,
           capture: :all_names
         ) do
      [graph_id, body] ->
        name =
          graph_id
          |> String.trim()
          |> normalize_id()
          |> case do
            "" -> "pipeline"
            normalized -> normalized
          end

        {:ok, name, body}

      _ ->
        {:error, "Invalid DOT input. Expected `digraph ... { ... }`."}
    end
  end

  defp split_statements(body) do
    body
    |> flatten_subgraphs()
    |> String.replace("\r", "")
    |> split_unquoted_statements()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 in ["", "{", "}"] or String.starts_with?(&1, "subgraph ")))
  end

  defp split_unquoted_statements(text) do
    {parts, current, _quote_char} =
      text
      |> String.graphemes()
      |> Enum.reduce({[], "", nil}, fn char, {parts, current, quote_char} ->
        cond do
          char in ["\"", "'"] and quote_char == nil ->
            {parts, current <> char, char}

          char == quote_char and not escaped_quote?(current) ->
            {parts, current <> char, nil}

          (char == ";" or char == "\n") and quote_char == nil ->
            {[current | parts], "", quote_char}

          true ->
            {parts, current <> char, quote_char}
        end
      end)

    [current | parts]
    |> Enum.reverse()
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  defp escaped_quote?(current) do
    trailing_backslashes =
      current
      |> String.reverse()
      |> String.graphemes()
      |> Enum.take_while(&(&1 == "\\"))
      |> length()

    rem(trailing_backslashes, 2) == 1
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

    if id == "" do
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
      |> split_edge_path()
      |> Enum.map(&normalize_id/1)
      |> Enum.reject(&(&1 == ""))

    if length(ids) < 2 do
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
    with {:ok, stylesheet_rules} <- ModelStylesheet.parse(graph.attrs["model_stylesheet"]) do
      finalized_nodes =
        graph.nodes
        |> Enum.map(fn {id, node} ->
          style_attrs = ModelStylesheet.attrs_for_node(stylesheet_rules, id, node.attrs)
          attrs = graph.node_defaults |> Map.merge(style_attrs) |> Map.merge(node.attrs)
          {id, Node.new(id, attrs)}
        end)
        |> Map.new()

      {:ok, %{graph | nodes: finalized_nodes}}
    end
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
    {parts, current, _quote_char} =
      text
      |> String.graphemes()
      |> Enum.reduce({[], "", nil}, fn char, {parts, current, quote_char} ->
        cond do
          char in ["\"", "'"] and quote_char == nil ->
            {parts, current <> char, char}

          char == quote_char and not escaped_quote?(current) ->
            {parts, current <> char, nil}

          char == "," and quote_char == nil ->
            {[current | parts], "", quote_char}

          true ->
            {parts, current <> char, quote_char}
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
      |> strip_wrapping_quotes()
      |> String.replace("\\\"", "\"")
      |> String.replace("\\'", "'")
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

  defp strip_wrapping_quotes(<<quote, rest::binary>>) when quote in [?", ?'] do
    terminal = <<quote>>

    if String.ends_with?(rest, terminal) do
      binary_part(rest, 0, byte_size(rest) - 1)
    else
      rest
    end
  end

  defp strip_wrapping_quotes(value), do: value

  defp normalize_id(id) do
    trimmed = String.trim(id)

    cond do
      trimmed == "" ->
        ""

      Regex.match?(~r/^"([^"\\]|\\.)*"$/, trimmed) ->
        trimmed
        |> String.trim_leading("\"")
        |> String.trim_trailing("\"")
        |> String.replace("\\\"", "\"")
        |> String.replace("\\\\", "\\")

      Regex.match?(~r/^'([^'\\]|\\.)*'$/, trimmed) ->
        trimmed
        |> String.trim_leading("'")
        |> String.trim_trailing("'")
        |> String.replace("\\'", "'")
        |> String.replace("\\\\", "\\")

      Regex.match?(@bare_id_pattern, trimmed) ->
        trimmed

      Regex.match?(@numeric_id_pattern, trimmed) ->
        trimmed

      true ->
        ""
    end
  end

  defp split_edge_path(text) do
    {parts, current, _quote_char} =
      text
      |> String.graphemes()
      |> Enum.reduce({[], "", nil}, fn char, {parts, current, quote_char} ->
        cond do
          char in ["\"", "'"] and quote_char == nil ->
            {parts, current <> char, char}

          char == quote_char and not escaped_quote?(current) ->
            {parts, current <> char, nil}

          char == ">" and quote_char == nil and String.ends_with?(current, "-") ->
            segment = String.slice(current, 0, max(String.length(current) - 1, 0))
            {parts ++ [segment], "", quote_char}

          true ->
            {parts, current <> char, quote_char}
        end
      end)

    parts ++ [current]
  end

  defp strip_comments(dot) do
    do_strip_comments(dot, [], nil, false, :normal)
    |> IO.iodata_to_binary()
  end

  defp do_strip_comments(<<>>, acc, _quote, _escaped, :normal), do: Enum.reverse(acc)
  defp do_strip_comments(<<>>, acc, _quote, _escaped, :line_comment), do: Enum.reverse(acc)
  defp do_strip_comments(<<>>, acc, _quote, _escaped, :block_comment), do: Enum.reverse(acc)

  defp do_strip_comments(<<char, rest::binary>>, acc, quote, escaped, :normal) do
    cond do
      quote == nil and char == ?/ and match?(<<?/, _::binary>>, rest) ->
        <<_slash, next::binary>> = rest
        do_strip_comments(next, acc, nil, false, :line_comment)

      quote == nil and char == ?/ and match?(<<?*, _::binary>>, rest) ->
        <<_star, next::binary>> = rest
        do_strip_comments(next, acc, nil, false, :block_comment)

      char in [?", ?'] and quote == nil ->
        do_strip_comments(rest, [<<char>> | acc], char, false, :normal)

      char == quote and not escaped ->
        do_strip_comments(rest, [<<char>> | acc], nil, false, :normal)

      true ->
        next_escaped = quote != nil and char == ?\\ and not escaped
        do_strip_comments(rest, [<<char>> | acc], quote, next_escaped, :normal)
    end
  end

  defp do_strip_comments(<<char, rest::binary>>, acc, quote, _escaped, :line_comment) do
    if char == ?\n do
      do_strip_comments(rest, [<<"\n">> | acc], quote, false, :normal)
    else
      do_strip_comments(rest, acc, quote, false, :line_comment)
    end
  end

  defp do_strip_comments(<<"*/", rest::binary>>, acc, quote, _escaped, :block_comment) do
    do_strip_comments(rest, acc, quote, false, :normal)
  end

  defp do_strip_comments(<<_char, rest::binary>>, acc, quote, _escaped, :block_comment) do
    do_strip_comments(rest, acc, quote, false, :block_comment)
  end

  defp flatten_subgraphs(body) do
    flattened =
      Regex.replace(
        ~r/subgraph\s+("?[\w\-]+"?)?\s*\{([^{}]*)\}/ms,
        body,
        "\\2"
      )

    if flattened == body, do: body, else: flatten_subgraphs(flattened)
  end
end
