defmodule AttractorEx.Parser do
  @moduledoc """
  Parses the supported Attractor DOT subset into `AttractorEx.Graph`.

  The parser focuses on the executable subset used by the engine rather than full
  Graphviz grammar parity. It also finalizes parsed graphs by applying model stylesheet
  rules and normalizing nodes into runtime structs.
  """

  alias AttractorEx.{Edge, Graph, ModelStylesheet, Node}

  @bare_id_pattern ~r/^(?:[A-Za-z_][A-Za-z0-9_]*|-?(?:\.\d+|\d+(?:\.\d*)?))$/
  @bare_graph_id_pattern ~r/^[A-Za-z_][A-Za-z0-9_\-]*$/
  @quoted_id_pattern ~r/^"(?:[^"\\]|\\.)+"$|^'(?:[^'\\]|\\.)+'$/
  @compass_points ~w(n ne e se s sw w nw c _)
  @graph_attr_decl_pattern ~r/^([A-Za-z_][A-Za-z0-9_\.]*)\s*=\s*(.+)$/
  @attr_statement_pattern ~r/^(graph|node|edge)\b(.*)$/s
  @root_pattern ~r/^\s*(?:strict\s+)?digraph\s+((?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|<[^>]+>|[A-Za-z_][A-Za-z0-9_\-]*))?\s*\{(?<body>.*)\}\s*$/ms
  @root_name_pattern ~r/^\s*(?:strict\s+)?digraph\s+((?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|<[^>]+>|[A-Za-z_][A-Za-z0-9_\-]*))?\s*\{/m
  @type parse_scope :: %{
          node_defaults: map(),
          edge_defaults: map(),
          classes: [String.t()],
          graph_attrs: map()
        }

  @doc "Parses DOT source into a normalized `AttractorEx.Graph`."
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
           @root_pattern,
           dot,
           capture: :all_names
         ) do
      [body] ->
        name =
          case Regex.run(
                 @root_name_pattern,
                 dot,
                 capture: :all_but_first
               ) do
            [value] ->
              candidate = normalize_graph_identifier(value)

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

  defp parse_statement(statement, graph, scope, opts) do
    case Regex.run(@attr_statement_pattern, statement, capture: :all_but_first) do
      ["graph", rest] ->
        attrs = rest |> String.trim() |> parse_attribute_blocks()

        if opts[:top_level?] do
          {:ok, %{graph | attrs: Map.merge(graph.attrs, attrs)}, scope}
        else
          {:ok, graph, %{scope | graph_attrs: Map.merge(scope.graph_attrs, attrs)}}
        end

      ["node", rest] ->
        attrs = rest |> String.trim() |> parse_attribute_blocks()
        next_scope = %{scope | node_defaults: Map.merge(scope.node_defaults, attrs)}

        if opts[:top_level?] do
          {:ok, %{graph | node_defaults: Map.merge(graph.node_defaults, attrs)}, next_scope}
        else
          {:ok, graph, next_scope}
        end

      ["edge", rest] ->
        attrs = rest |> String.trim() |> parse_attribute_blocks()
        next_scope = %{scope | edge_defaults: Map.merge(scope.edge_defaults, attrs)}

        if opts[:top_level?] do
          {:ok, %{graph | edge_defaults: Map.merge(graph.edge_defaults, attrs)}, next_scope}
        else
          {:ok, graph, next_scope}
        end

      _ ->
        parse_non_attr_statement(statement, graph, scope, opts)
    end
  end

  defp parse_non_attr_statement(statement, graph, scope, opts) do
    cond do
      String.contains?(statement, "--") ->
        {:error, "Undirected edges are not supported. Use `->`."}

      edge_statement?(statement) ->
        parse_edge_statement(statement, graph, scope)

      subgraph_statement?(statement) ->
        parse_inline_subgraph(statement, graph, scope)

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

    with {:ok, endpoint_groups, graph_after_endpoints} <-
           parse_edge_endpoints(path_part, graph, scope) do
      case endpoint_groups do
        [_single] ->
          {:error, "Invalid edge declaration: #{statement}"}

        _ ->
          base_attrs = Map.merge(scope.edge_defaults, parse_attribute_blocks(attrs_part))
          next_graph = connect_endpoint_groups(endpoint_groups, graph_after_endpoints, base_attrs)
          {:ok, next_graph, scope}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp append_edge(graph, from, to, attrs) do
    edge = Edge.new(from, to, attrs)
    %{graph | edges: graph.edges ++ [edge]}
  end

  defp maybe_put_port_attr(attrs, _key, nil), do: attrs
  defp maybe_put_port_attr(attrs, key, port), do: Map.put(attrs, key, port)

  defp connect_endpoint_groups(endpoint_groups, graph, base_attrs) do
    endpoint_groups
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(graph, fn [from_group, to_group], acc ->
      connect_endpoint_group_pair(from_group, to_group, acc, base_attrs)
    end)
  end

  defp connect_endpoint_group_pair(from_group, to_group, graph, base_attrs) do
    Enum.reduce(from_group, graph, fn from, group_acc ->
      Enum.reduce(to_group, group_acc, fn to, edge_acc ->
        attrs =
          base_attrs
          |> maybe_put_port_attr("tailport", from.port)
          |> maybe_put_port_attr("headport", to.port)

        edge_acc
        |> ensure_node(from.id)
        |> ensure_node(to.id)
        |> append_edge(from.id, to.id, attrs)
      end)
    end)
  end

  defp parse_inline_subgraph(statement, graph, scope) do
    with {:ok, body, rest} <- take_subgraph(String.trim(statement)),
         "" <- String.trim(rest) do
      subgraph_scope = %{
        node_defaults: scope.node_defaults,
        edge_defaults: scope.edge_defaults,
        classes: scope.classes,
        graph_attrs: %{}
      }

      parse_block(body, graph, subgraph_scope, top_level?: false)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, "Invalid subgraph declaration."}
    end
  end

  defp parse_edge_endpoints(path_part, graph, scope) do
    path_part
    |> split_edge_path()
    |> Enum.reduce_while({:ok, [], graph}, fn segment, {:ok, endpoint_groups, acc_graph} ->
      case parse_edge_endpoint(segment, acc_graph, scope) do
        {:ok, parsed_group, next_graph} ->
          {:cont, {:ok, endpoint_groups ++ [parsed_group], next_graph}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp parse_edge_endpoint(segment, graph, scope) do
    trimmed = String.trim(segment)

    cond do
      trimmed == "" ->
        {:error, "Invalid edge declaration: #{segment}"}

      subgraph_statement?(trimmed) ->
        parse_subgraph_endpoint(trimmed, graph, scope)

      true ->
        parse_node_endpoint(trimmed, graph)
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
    do_split_attrs(statement, "", scanner_state())
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

  defp take_attribute_block("[" <> rest),
    do: do_take_attribute_block(rest, "", scanner_state(bracket_depth: 1))

  defp take_attribute_block(_text), do: :error

  defp do_take_attribute_block(<<>>, _current, _state), do: :error

  defp do_take_attribute_block(<<char, rest::binary>>, current, state) do
    next_state = advance_scanner_state(state, char, current)

    cond do
      scanner_opening_bracket?(state, char) ->
        do_take_attribute_block(rest, current <> <<char>>, next_state)

      scanner_closing_bracket?(state, char) and state.bracket_depth == 1 ->
        {:ok, current, rest}

      true ->
        do_take_attribute_block(rest, current <> <<char>>, next_state)
    end
  end

  defp split_attr_pairs(text) do
    {parts, current, _state} =
      text
      |> String.graphemes()
      |> Enum.reduce({[], "", scanner_state()}, &consume_attr_pair_char/2)

    [current | parts]
    |> Enum.reverse()
    |> Enum.reject(&(String.trim(&1) == ""))
  end

  defp consume_attr_pair_char(char, {parts, current, state}) do
    next_state = advance_scanner_state(state, char, current)

    if attr_pair_separator?(char, state) do
      {[current | parts], "", state}
    else
      {parts, current <> char, next_state}
    end
  end

  defp attr_pair_separator?(char, state),
    do:
      scanner_plain?(state) and state.bracket_depth == 0 and state.brace_depth == 0 and
        char_code(char) in [?,, ?;, ?\n]

  defp parse_value(value) do
    normalized =
      value
      |> String.trim()
      |> unquote_and_unescape()

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

  defp unquote_and_unescape(value) do
    value
    |> strip_wrapping_quotes()
    |> String.replace("\\n", "\n")
    |> String.replace("\\r", "\r")
    |> String.replace("\\t", "\t")
    |> String.replace("\\\"", "\"")
    |> String.replace("\\'", "'")
    |> String.replace("\\\\", "\\")
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
    {parts, current, _state} =
      text
      |> String.graphemes()
      |> Enum.reduce({[], "", scanner_state()}, fn char, {parts, current, state} ->
        cond do
          char_code(char) == ?> and scanner_plain?(state) and String.ends_with?(current, "-") ->
            segment = String.slice(current, 0, max(String.length(current) - 1, 0))
            {parts ++ [segment], "", state}

          true ->
            next_state = advance_scanner_state(state, char, current)
            {parts, current <> char, next_state}
        end
      end)

    parts ++ [current]
  end

  defp strip_comments(dot) do
    do_strip_comments(dot, [], scanner_state(), :normal)
    |> IO.iodata_to_binary()
  end

  defp do_strip_comments(<<>>, acc, _state, :normal), do: Enum.reverse(acc)
  defp do_strip_comments(<<>>, acc, _state, :line_comment), do: Enum.reverse(acc)
  defp do_strip_comments(<<>>, acc, _state, :block_comment), do: Enum.reverse(acc)

  defp do_strip_comments(<<char, rest::binary>>, acc, state, :normal) do
    cond do
      scanner_plain?(state) and char == ?/ and match?(<<?/, _::binary>>, rest) ->
        <<_slash, next::binary>> = rest
        do_strip_comments(next, acc, state, :line_comment)

      scanner_plain?(state) and char == ?/ and match?(<<?*, _::binary>>, rest) ->
        <<_star, next::binary>> = rest
        do_strip_comments(next, acc, state, :block_comment)

      true ->
        next_state = advance_scanner_state(state, char, "")
        do_strip_comments(rest, [<<char>> | acc], next_state, :normal)
    end
  end

  defp do_strip_comments(<<char, rest::binary>>, acc, state, :line_comment) do
    if char == ?\n do
      do_strip_comments(rest, [<<"\n">> | acc], state, :normal)
    else
      do_strip_comments(rest, acc, state, :line_comment)
    end
  end

  defp do_strip_comments(<<"*/", rest::binary>>, acc, state, :block_comment) do
    do_strip_comments(rest, acc, state, :normal)
  end

  defp do_strip_comments(<<_char, rest::binary>>, acc, state, :block_comment) do
    do_strip_comments(rest, acc, state, :block_comment)
  end

  defp do_split_items(text, acc) do
    trimmed = String.trim_leading(text)

    cond do
      trimmed == "" ->
        {:ok, Enum.reverse(acc)}

      String.starts_with?(trimmed, "subgraph") ->
        with {:ok, body, rest} <- take_subgraph(trimmed) do
          if String.starts_with?(String.trim_leading(rest), "->") do
            split_statement_item(trimmed, acc)
          else
            with {:ok, next_rest} <- consume_statement_separator(rest) do
              do_split_items(next_rest, [{:subgraph, body} | acc])
            end
          end
        end

      true ->
        split_statement_item(trimmed, acc)
    end
  end

  defp split_statement_item(text, acc) do
    with {:ok, statement, rest} <- take_statement(text),
         {:ok, next_rest} <- consume_statement_separator(rest) do
      case String.trim(statement) do
        "" -> do_split_items(next_rest, acc)
        value -> do_split_items(next_rest, [{:statement, value} | acc])
      end
    end
  end

  defp take_statement(text) do
    do_take_statement(text, "", scanner_state())
  end

  defp do_take_statement(<<>>, current, _state),
    do: {:ok, current, ""}

  defp do_take_statement(<<char, rest::binary>>, current, state) do
    cond do
      statement_terminator?(char, state) ->
        {:ok, current, rest}

      true ->
        next_state = advance_scanner_state(state, char, current)
        do_take_statement(rest, current <> <<char>>, next_state)
    end
  end

  defp take_subgraph(text) do
    with {:ok, body_start, rest} <- take_until_open_brace(text),
         true <-
           String.trim(body_start) =~
             ~r/^subgraph(\s+(?:"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|[A-Za-z_][A-Za-z0-9_\-]*))?$/ do
      take_balanced_block(rest, "", scanner_state(), 1)
    else
      false -> {:error, "Invalid subgraph declaration."}
      {:error, reason} -> {:error, reason}
    end
  end

  defp take_until_open_brace(text), do: do_take_until_open_brace(text, "", scanner_state())

  defp do_take_until_open_brace(<<>>, _current, _state),
    do: {:error, "Invalid subgraph declaration."}

  defp do_take_until_open_brace(<<char, rest::binary>>, current, state) do
    cond do
      char == ?{ and scanner_plain?(state) ->
        {:ok, current, rest}

      true ->
        next_state = advance_scanner_state(state, char, current)
        do_take_until_open_brace(rest, current <> <<char>>, next_state)
    end
  end

  defp take_balanced_block(text, current, _quote, 0), do: {:ok, current, text}
  defp take_balanced_block(<<>>, _current, _quote, _depth), do: {:error, "Unterminated subgraph."}

  defp take_balanced_block(<<char, rest::binary>>, current, state, depth) do
    next_state = advance_scanner_state(state, char, current)

    cond do
      char == ?{ and scanner_plain?(state) ->
        take_balanced_block(rest, current <> <<char>>, next_state, depth + 1)

      char == ?} and scanner_plain?(state) and depth == 1 ->
        {:ok, current, rest}

      char == ?} and scanner_plain?(state) ->
        take_balanced_block(rest, current <> <<char>>, next_state, depth - 1)

      true ->
        take_balanced_block(rest, current <> <<char>>, next_state, depth)
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

  defp do_split_attrs(<<>>, current, _state), do: {String.trim(current), "[]"}

  defp do_split_attrs(<<char, rest::binary>>, current, state) do
    cond do
      scanner_opening_bracket?(state, char) and state.brace_depth == 0 ->
        {String.trim(current), "[" <> rest}

      true ->
        next_state = advance_scanner_state(state, char, current)
        do_split_attrs(rest, current <> <<char>>, next_state)
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
        |> unquote_and_unescape()
        |> String.trim()

      html_identifier?(trimmed) ->
        trimmed

      true ->
        ""
    end
  end

  defp normalize_graph_identifier(id) do
    trimmed = String.trim(id)

    cond do
      trimmed == "" ->
        ""

      Regex.match?(@bare_graph_id_pattern, trimmed) ->
        trimmed

      Regex.match?(@quoted_id_pattern, trimmed) ->
        trimmed
        |> unquote_and_unescape()
        |> String.trim()

      html_identifier?(trimmed) ->
        trimmed

      true ->
        ""
    end
  end

  defp parse_subgraph_endpoint(segment, graph, scope) do
    with {:ok, body, rest} <- take_subgraph(segment),
         "" <- String.trim(rest) do
      subgraph_scope = %{
        node_defaults: scope.node_defaults,
        edge_defaults: scope.edge_defaults,
        classes: scope.classes,
        graph_attrs: %{}
      }

      with {:ok, next_graph, _scope} <-
             parse_block(body, graph, subgraph_scope, top_level?: false),
           {:ok, endpoint_graph, _scope} <-
             parse_block(body, %Graph{}, subgraph_scope, top_level?: false) do
        endpoints =
          endpoint_graph.nodes
          |> Map.keys()
          |> Enum.sort()
          |> Enum.map(&%{id: &1, port: nil})

        {:ok, endpoints, next_graph}
      end
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, "Invalid subgraph declaration."}
    end
  end

  defp parse_node_endpoint(segment, graph) do
    case split_port_parts(segment) do
      [] ->
        {:error, "Invalid edge declaration: #{segment}"}

      [base | suffixes] ->
        id = normalize_id(base)

        if id == "" do
          {:error, "Invalid edge declaration: #{segment}"}
        else
          {:ok, [%{id: id, port: normalize_port_suffix(suffixes)}], ensure_node(graph, id)}
        end
    end
  end

  defp split_port_parts(text) do
    {parts, current, _state} =
      text
      |> String.graphemes()
      |> Enum.reduce({[], "", scanner_state()}, fn char, {parts, current, state} ->
        cond do
          char_code(char) == ?: and scanner_plain?(state) ->
            {parts ++ [current], "", state}

          true ->
            next_state = advance_scanner_state(state, char, current)
            {parts, current <> char, next_state}
        end
      end)

    (parts ++ [current])
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_port_suffix([]), do: nil

  defp normalize_port_suffix([single]) when single in @compass_points,
    do: single

  defp normalize_port_suffix(parts), do: Enum.join(parts, ":")

  defp scanner_state(overrides \\ []) do
    %{quote: nil, escaped: false, bracket_depth: 0, brace_depth: 0, html_depth: 0}
    |> Map.merge(Map.new(overrides))
  end

  defp scanner_plain?(state) do
    is_nil(state.quote) and state.html_depth == 0
  end

  defp scanner_opening_bracket?(state, char), do: scanner_plain?(state) and char_code(char) == ?[
  defp scanner_closing_bracket?(state, char), do: scanner_plain?(state) and char_code(char) == ?]

  defp statement_terminator?(char, state) do
    scanner_plain?(state) and state.bracket_depth == 0 and state.brace_depth == 0 and
      char_code(char) in [?\n, ?;]
  end

  defp advance_scanner_state(state, char, current) do
    code = char_code(char)

    cond do
      opening_quote?(state, code, current) ->
        %{state | quote: code, escaped: false}

      closing_quote?(state, code) ->
        %{state | quote: nil, escaped: false}

      in_quote?(state) ->
        %{state | escaped: escaping_char?(code, state)}

      true ->
        advance_plain_scanner_state(state, code)
    end
  end

  defp edge_statement?(statement) do
    statement
    |> split_edge_path()
    |> length()
    |> Kernel.>(1)
  end

  defp char_code(char) when is_integer(char), do: char
  defp char_code(char) when is_binary(char), do: :binary.first(char)

  defp opening_quote?(state, code, current) do
    code in [?", ?'] and not in_quote?(state) and state.html_depth == 0 and
      not escaped_quote?(current)
  end

  defp closing_quote?(state, code), do: code == state.quote and not state.escaped
  defp in_quote?(state), do: not is_nil(state.quote)
  defp escaping_char?(code, state), do: code == ?\\ and not state.escaped

  defp advance_plain_scanner_state(state, code) do
    cond do
      code == ?< -> %{state | html_depth: state.html_depth + 1}
      code == ?> and state.html_depth > 0 -> %{state | html_depth: state.html_depth - 1}
      code == ?[ -> %{state | bracket_depth: state.bracket_depth + 1}
      code == ?] and state.bracket_depth > 0 -> %{state | bracket_depth: state.bracket_depth - 1}
      code == ?{ -> %{state | brace_depth: state.brace_depth + 1}
      code == ?} and state.brace_depth > 0 -> %{state | brace_depth: state.brace_depth - 1}
      true -> %{state | escaped: false}
    end
  end

  defp subgraph_statement?(statement) do
    String.trim_leading(statement)
    |> String.starts_with?("subgraph")
  end

  defp html_identifier?(trimmed) do
    String.starts_with?(trimmed, "<") and String.ends_with?(trimmed, ">") and
      balanced_html?(trimmed)
  end

  defp balanced_html?(text) do
    final_depth =
      text
      |> String.graphemes()
      |> Enum.reduce_while(0, fn char, depth ->
        cond do
          char == "<" -> {:cont, depth + 1}
          char == ">" and depth > 0 -> {:cont, depth - 1}
          char == ">" -> {:halt, :error}
          true -> {:cont, depth}
        end
      end)

    final_depth == 0
  end
end
