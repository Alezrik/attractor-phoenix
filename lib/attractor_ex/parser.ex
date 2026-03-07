defmodule AttractorEx.Parser do
  @moduledoc false

  alias AttractorEx.{Edge, Graph, ModelStylesheet, Node}

  @bare_id_pattern ~r/^[A-Za-z_][A-Za-z0-9_]*$/
  @quoted_id_pattern ~r/^"(?:[^"\\]|\\.)+"$|^'(?:[^'\\]|\\.)+'$/
  @graph_attr_decl_pattern ~r/^([A-Za-z_][A-Za-z0-9_\.]*)\s*=\s*(.+)$/
  @type parse_scope :: %{
          node_defaults: map(),
          edge_defaults: map(),
          classes: [String.t()],
          graph_attrs: map()
        }

  def parse(dot) when is_binary(dot) do
    cleaned = strip_comments(dot)

    with {:ok, graph_name, body} <- parse_root(cleaned) do
      graph = %Graph{id: graph_name}
      scope = %{node_defaults: %{}, edge_defaults: %{}, classes: [], graph_attrs: %{}}

      case parse_block(body, graph, scope, top_level?: true) do
        {:error, reason} -> {:error, reason}
        {:ok, graph_value, _scope} -> finalize_graph(graph_value)
      end
    end
  end

  defp parse_root(dot) do
    case Regex.run(
           ~r/digraph\s+((?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|[A-Za-z_][A-Za-z0-9_\-]*))?\s*\{(?<body>.*)\}\s*$/ms,
           dot,
           capture: :all_names
         ) do
      [body] ->
        name =
          case Regex.run(
                 ~r/digraph\s+((?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|[A-Za-z_][A-Za-z0-9_\-]*))?\s*\{/m,
                 dot,
                 capture: :all_but_first
               ) do
            [value] ->
              candidate = normalize_identifier(value)

              if candidate != "", do: candidate, else: "pipeline"

            _ ->
              "pipeline"
          end

        {:ok, name, body}

      _ ->
        {:error, "Invalid DOT input. Expected `digraph ... { ... }`."}
    end
  end

  defp parse_block(body, graph, scope, opts) do
    with {:ok, items} <- split_items(body) do
      subgraph_class = derived_subgraph_class(items)

      scope =
        if opts[:top_level?] or is_nil(subgraph_class) do
          scope
        else
          %{scope | classes: scope.classes ++ [subgraph_class]}
        end

      Enum.reduce_while(items, {:ok, graph, scope}, fn item, {:ok, acc_graph, acc_scope} ->
        case parse_item(item, acc_graph, acc_scope, opts) do
          {:ok, next_graph, next_scope} -> {:cont, {:ok, next_graph, next_scope}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp parse_item({:statement, statement}, graph, scope, opts) do
    parse_statement(statement, graph, scope, opts)
  end

  defp parse_item({:subgraph, body}, graph, scope, _opts) do
    subgraph_scope = %{
      node_defaults: scope.node_defaults,
      edge_defaults: scope.edge_defaults,
      classes: scope.classes,
      graph_attrs: %{}
    }

    parse_block(body, graph, subgraph_scope, top_level?: false)
  end

  defp split_items(body) do
    do_split_items(String.replace(body, "\r", ""), [])
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

  defp parse_statement("graph " <> rest, graph, scope, opts) do
    attrs = rest |> String.trim() |> parse_attribute_blocks()

    if opts[:top_level?] do
      {:ok, %{graph | attrs: Map.merge(graph.attrs, attrs)}, scope}
    else
      {:ok, graph, %{scope | graph_attrs: Map.merge(scope.graph_attrs, attrs)}}
    end
  end

  defp parse_statement("node " <> rest, graph, scope, opts) do
    attrs = rest |> String.trim() |> parse_attribute_blocks()
    next_scope = %{scope | node_defaults: Map.merge(scope.node_defaults, attrs)}

    if opts[:top_level?] do
      {:ok, %{graph | node_defaults: Map.merge(graph.node_defaults, attrs)}, next_scope}
    else
      {:ok, graph, next_scope}
    end
  end

  defp parse_statement("edge " <> rest, graph, scope, opts) do
    attrs = rest |> String.trim() |> parse_attribute_blocks()
    next_scope = %{scope | edge_defaults: Map.merge(scope.edge_defaults, attrs)}

    if opts[:top_level?] do
      {:ok, %{graph | edge_defaults: Map.merge(graph.edge_defaults, attrs)}, next_scope}
    else
      {:ok, graph, next_scope}
    end
  end

  defp parse_statement(statement, graph, scope, opts) do
    cond do
      String.contains?(statement, "--") ->
        {:error, "Undirected edges are not supported. Use `->`."}

      String.contains?(statement, "->") ->
        parse_edge_statement(statement, graph, scope)

      Regex.match?(@graph_attr_decl_pattern, statement) ->
        parse_graph_attr_decl(statement, graph, scope, opts)

      true ->
        parse_node_statement(statement, graph, scope)
    end
  end

  defp parse_graph_attr_decl(statement, graph, scope, opts) do
    case Regex.run(@graph_attr_decl_pattern, statement, capture: :all_but_first) do
      [key, value] ->
        parsed = parse_value(value)

        if opts[:top_level?] do
          {:ok, %{graph | attrs: Map.put(graph.attrs, key, parsed)}, scope}
        else
          {:ok, graph, %{scope | graph_attrs: Map.put(scope.graph_attrs, key, parsed)}}
        end

      _ ->
        {:error, "Invalid graph attribute declaration: #{statement}"}
    end
  end

  defp parse_node_statement(statement, graph, scope) do
    {id_part, attrs_part} = split_attrs(statement)
    id = normalize_id(id_part)

    if id == "" do
      {:error, "Invalid node declaration: #{statement}"}
    else
      attrs =
        scope.node_defaults
        |> Map.merge(parse_attribute_blocks(attrs_part))
        |> merge_class_attr(scope.classes)

      existing =
        case Map.get(graph.nodes, id) do
          nil -> %Node{id: id, attrs: %{}}
          node -> node
        end

      merged_attrs =
        existing.attrs
        |> Map.merge(attrs)
        |> merge_class_attr(class_tokens(existing.attrs["class"]))

      merged = %{existing | attrs: merged_attrs}
      {:ok, %{graph | nodes: Map.put(graph.nodes, id, merged)}, scope}
    end
  end

  defp parse_edge_statement(statement, graph, scope) do
    {path_part, attrs_part} = split_attrs(statement)

    ids =
      path_part
      |> split_edge_path()
      |> Enum.map(&normalize_id/1)
      |> Enum.reject(&(&1 == ""))

    if length(ids) < 2 do
      {:error, "Invalid edge declaration: #{statement}"}
    else
      attrs = Map.merge(scope.edge_defaults, parse_attribute_blocks(attrs_part))

      next_graph =
        ids
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.reduce(graph, fn [from, to], acc ->
          with_from = ensure_node(acc, from)
          with_nodes = ensure_node(with_from, to)
          edge = Edge.new(from, to, attrs)
          %{with_nodes | edges: with_nodes.edges ++ [edge]}
        end)

      {:ok, next_graph, scope}
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
          attrs = Map.merge(style_attrs, node.attrs)
          {id, Node.new(id, attrs)}
        end)
        |> Map.new()

      {:ok, %{graph | nodes: finalized_nodes}}
    end
  end

  defp split_attrs(statement) do
    do_split_attrs(statement, "", nil)
  end

  defp parse_attribute_blocks(text) when is_binary(text) do
    text
    |> String.trim()
    |> do_parse_attribute_blocks(%{})
  end

  defp do_parse_attribute_blocks("[" <> _rest = text, acc) do
    case take_attribute_block(text) do
      {:ok, block, rest} ->
        block_attrs =
          block
          |> split_attr_pairs()
          |> Enum.map(&String.trim/1)
          |> Enum.reduce(%{}, fn pair, block_acc ->
            case String.split(pair, "=", parts: 2) do
              [key, value] ->
                Map.put(block_acc, String.trim(key), parse_value(value))

              _ ->
                block_acc
            end
          end)

        do_parse_attribute_blocks(String.trim_leading(rest), Map.merge(acc, block_attrs))

      :error ->
        acc
    end
  end

  defp do_parse_attribute_blocks(_text, acc), do: acc

  defp take_attribute_block("[" <> rest), do: do_take_attribute_block(rest, "", nil, 1)
  defp take_attribute_block(_text), do: :error

  defp do_take_attribute_block(<<>>, _current, _quote, _depth), do: :error

  defp do_take_attribute_block(<<char, rest::binary>>, current, quote, depth) do
    cond do
      char in [?", ?'] and is_nil(quote) ->
        do_take_attribute_block(rest, current <> <<char>>, char, depth)

      char == quote ->
        do_take_attribute_block(rest, current <> <<char>>, nil, depth)

      is_nil(quote) and char == ?[ ->
        do_take_attribute_block(rest, current <> <<char>>, quote, depth + 1)

      is_nil(quote) and char == ?] and depth == 1 ->
        {:ok, current, rest}

      is_nil(quote) and char == ?] ->
        do_take_attribute_block(rest, current <> <<char>>, quote, depth - 1)

      true ->
        do_take_attribute_block(rest, current <> <<char>>, quote, depth)
    end
  end

  defp split_attr_pairs(text) do
    {parts, current, _in_quotes, _bracket_depth} =
      text
      |> String.graphemes()
      |> Enum.reduce({[], "", nil, 0}, fn char, {parts, current, quote, bracket_depth} ->
        cond do
          char in ["\"", "'"] and is_nil(quote) and not escaped_quote?(current) ->
            {parts, current <> char, char, bracket_depth}

          char == quote and not escaped_quote?(current) ->
            {parts, current <> char, nil, bracket_depth}

          char == "[" and is_nil(quote) ->
            {parts, current <> char, quote, bracket_depth + 1}

          char == "]" and is_nil(quote) and bracket_depth > 0 ->
            {parts, current <> char, quote, bracket_depth - 1}

          char in [",", ";"] and is_nil(quote) and bracket_depth == 0 ->
            {[current | parts], "", quote, bracket_depth}

          true ->
            {parts, current <> char, quote, bracket_depth}
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
    closing = <<quote>>

    if String.ends_with?(rest, closing) do
      binary_part(rest, 0, byte_size(rest) - 1)
    else
      rest
    end
  end

  defp strip_wrapping_quotes(value), do: value

  defp normalize_id(id), do: normalize_identifier(id)

  defp split_edge_path(text) do
    {parts, current, _quote} =
      text
      |> String.graphemes()
      |> Enum.reduce({[], "", nil}, fn char, {parts, current, quote} ->
        cond do
          char in ["\"", "'"] and is_nil(quote) and not escaped_quote?(current) ->
            {parts, current <> char, char}

          char == quote and not escaped_quote?(current) ->
            {parts, current <> char, nil}

          char == ">" and is_nil(quote) and String.ends_with?(current, "-") ->
            segment = String.slice(current, 0, max(String.length(current) - 1, 0))
            {parts ++ [segment], "", quote}

          true ->
            {parts, current <> char, quote}
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

  defp do_split_items(text, acc) do
    trimmed = String.trim_leading(text)

    cond do
      trimmed == "" ->
        {:ok, Enum.reverse(acc)}

      String.starts_with?(trimmed, "subgraph") ->
        with {:ok, body, rest} <- take_subgraph(trimmed),
             {:ok, next_rest} <- consume_statement_separator(rest) do
          do_split_items(next_rest, [{:subgraph, body} | acc])
        end

      true ->
        with {:ok, statement, rest} <- take_statement(trimmed),
             {:ok, next_rest} <- consume_statement_separator(rest) do
          case String.trim(statement) do
            "" -> do_split_items(next_rest, acc)
            value -> do_split_items(next_rest, [{:statement, value} | acc])
          end
        end
    end
  end

  defp take_statement(text) do
    do_take_statement(text, "", nil, false, 0)
  end

  defp do_take_statement(<<>>, current, _quote, _escaped, _bracket_depth),
    do: {:ok, current, ""}

  defp do_take_statement(<<char, rest::binary>>, current, quote, escaped, bracket_depth) do
    cond do
      char in [?", ?'] and is_nil(quote) ->
        do_take_statement(rest, current <> <<char>>, char, false, bracket_depth)

      char == quote and not escaped ->
        do_take_statement(rest, current <> <<char>>, nil, false, bracket_depth)

      quote != nil ->
        next_escaped = char == ?\\ and not escaped
        do_take_statement(rest, current <> <<char>>, quote, next_escaped, bracket_depth)

      char == ?[ ->
        do_take_statement(rest, current <> <<char>>, quote, false, bracket_depth + 1)

      char == ?] and bracket_depth > 0 ->
        do_take_statement(rest, current <> <<char>>, quote, false, bracket_depth - 1)

      bracket_depth == 0 and char in [?\n, ?;] ->
        {:ok, current, rest}

      true ->
        do_take_statement(rest, current <> <<char>>, quote, false, bracket_depth)
    end
  end

  defp take_subgraph(text) do
    with {:ok, body_start, rest} <- take_until_open_brace(text),
         true <-
           String.trim(body_start) =~
             ~r/^subgraph(\s+(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|[A-Za-z_][A-Za-z0-9_\-]*))?$/ do
      take_balanced_block(rest, "", nil, 1)
    else
      false -> {:error, "Invalid subgraph declaration."}
      {:error, reason} -> {:error, reason}
    end
  end

  defp take_until_open_brace(text), do: do_take_until_open_brace(text, "", nil, false)

  defp do_take_until_open_brace(<<>>, _current, _quote, _escaped),
    do: {:error, "Invalid subgraph declaration."}

  defp do_take_until_open_brace(<<char, rest::binary>>, current, quote, escaped) do
    cond do
      char in [?", ?'] and is_nil(quote) ->
        do_take_until_open_brace(rest, current <> <<char>>, char, false)

      char == quote and not escaped ->
        do_take_until_open_brace(rest, current <> <<char>>, nil, false)

      quote != nil ->
        next_escaped = char == ?\\ and not escaped
        do_take_until_open_brace(rest, current <> <<char>>, quote, next_escaped)

      char == ?{ ->
        {:ok, current, rest}

      true ->
        do_take_until_open_brace(rest, current <> <<char>>, quote, false)
    end
  end

  defp take_balanced_block(text, current, _quote, 0), do: {:ok, current, text}
  defp take_balanced_block(<<>>, _current, _quote, _depth), do: {:error, "Unterminated subgraph."}

  defp take_balanced_block(<<char, rest::binary>>, current, quote, depth) do
    cond do
      char in [?", ?'] and is_nil(quote) ->
        take_balanced_block(rest, current <> <<char>>, char, depth)

      char == quote ->
        take_balanced_block(rest, current <> <<char>>, nil, depth)

      is_nil(quote) and char == ?{ ->
        take_balanced_block(rest, current <> <<char>>, quote, depth + 1)

      is_nil(quote) and char == ?} and depth == 1 ->
        {:ok, current, rest}

      is_nil(quote) and char == ?} ->
        take_balanced_block(rest, current <> <<char>>, quote, depth - 1)

      true ->
        take_balanced_block(rest, current <> <<char>>, quote, depth)
    end
  end

  defp consume_statement_separator(text) do
    case String.trim_leading(text) do
      <<";", rest::binary>> -> {:ok, rest}
      other -> {:ok, other}
    end
  end

  defp derived_subgraph_class(items) do
    items
    |> Enum.find_value(&statement_label_value/1)
    |> normalize_class_name()
  end

  defp statement_label_value({:statement, "graph " <> rest}) do
    rest
    |> String.trim()
    |> parse_attribute_blocks()
    |> Map.get("label")
  end

  defp statement_label_value({:statement, statement}) do
    case Regex.run(@graph_attr_decl_pattern, statement, capture: :all_but_first) do
      ["label", value] -> parse_value(value)
      _ -> nil
    end
  end

  defp statement_label_value(_item), do: nil

  defp normalize_class_name(nil), do: nil

  defp normalize_class_name(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/[^a-z0-9\-]/, "")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
    |> case do
      "" -> nil
      class_name -> class_name
    end
  end

  defp merge_class_attr(attrs, classes) do
    merged_classes =
      attrs["class"]
      |> class_tokens()
      |> Kernel.++(classes)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    if merged_classes == [] do
      attrs
    else
      Map.put(attrs, "class", Enum.join(merged_classes, ","))
    end
  end

  defp class_tokens(nil), do: []

  defp class_tokens(value) do
    value
    |> to_string()
    |> String.split(~r/[,\s]+/, trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp do_split_attrs(<<>>, current, _quote), do: {String.trim(current), "[]"}

  defp do_split_attrs(<<char, rest::binary>>, current, quote) do
    cond do
      char in [?", ?'] and is_nil(quote) and not escaped_quote?(current) ->
        do_split_attrs(rest, current <> <<char>>, char)

      char == quote and not escaped_quote?(current) ->
        do_split_attrs(rest, current <> <<char>>, nil)

      char == ?[ and is_nil(quote) ->
        {String.trim(current), "[" <> rest}

      true ->
        do_split_attrs(rest, current <> <<char>>, quote)
    end
  end

  defp normalize_identifier(nil), do: ""

  defp normalize_identifier(id) do
    trimmed = String.trim(id)

    cond do
      trimmed == "" ->
        ""

      Regex.match?(@bare_id_pattern, trimmed) ->
        trimmed

      Regex.match?(@quoted_id_pattern, trimmed) ->
        trimmed
        |> strip_wrapping_quotes()
        |> String.replace("\\\"", "\"")
        |> String.replace("\\'", "'")
        |> String.replace("\\\\", "\\")
        |> String.trim()

      true ->
        ""
    end
  end
end
